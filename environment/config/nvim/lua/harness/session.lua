local lazy = require('core.lazy')

local Connection = require('harness.acp.connection')
local History = require('harness.session.History')
local Object = require('core.Object')
local PermissionGate = require('harness.session.PermissionGate')
local PromptQueue = require('harness.session.PromptQueue')
local SessionConfig = require('harness.session.SessionConfig')
local Subagents = require('harness.session.Subagents')
local Timer = require('core.Timer')
local async = require('harness.async')
local editor_context = require('harness.context')
local dataclass = require('core.dataclass')
local events = require('harness.events')
local permissions = require('harness.permissions')

local console = lazy('core.console')

local K = events.KIND

local Session = Object:extend()

Session.STATE = dataclass.enum({ 'idle', 'running', 'closed' })

local STATE_EVENTS = { [K.config] = true, [K.mode] = true, [K.commands] = true, [K.subagent] = true }

function Session.is_state_event(event)
  return STATE_EVENTS[event.kind] == true
end

function Session.blocks_of(text, captured, capabilities)
  local blocks = editor_context.blocks(captured, capabilities)

  blocks[#blocks + 1] = { type = 'text', text = text }

  return blocks
end

Session.choices = SessionConfig.choices

function Session:constructor(opts)
  local session = {
    key = opts.key,
    id = opts.id,
    agent = opts.agent,
    dir = opts.dir,
    connection = opts.connection,
    approve = opts.approve or permissions.new(),
    parent = opts.parent,
    depth = opts.depth or 0,
    title = opts.title,
    state = Session.STATE.idle,
    reloading = false,
    options = {},
    modes = nil,
    commands = {},
    _listeners = {},
    _tools = {},
    _turn = nil,
  }

  session.log = History()
  session.history = session.log.events
  session.times = session.log.times
  session.permissions = PermissionGate(session)
  session._pending = session.permissions.pending
  session.prompts = PromptQueue(session)
  session.queue = session.prompts.items
  session.config = SessionConfig(session)
  session.subagents = Subagents(session)
  session.children = session.subagents.children

  return session
end

function Session:attach()
  self.connection:attach(self.id, {
    update = function(update)
      self:_on_update(update)
    end,
    request = function(method, params)
      return self:_on_request(method, params)
    end,
    close = function(reason)
      self:_on_close(reason)
    end,
  })

  return self
end

function Session:subscribe(fn)
  local listener = { fn = fn }

  self._listeners[#self._listeners + 1] = listener

  return function()
    for i, candidate in ipairs(self._listeners) do
      if candidate == listener then table.remove(self._listeners, i) end
    end
  end
end

function Session:_notify(event)
  for _, listener in ipairs(vim.list_slice(self._listeners)) do
    local ok, err = pcall(listener.fn, event, self)

    if not ok then console.warn('Harness: a session listener failed: ' .. tostring(err)) end
  end
end

function Session:_emit(event)
  if self.log:append(event) then self:_notify(self.log:last()) end
end

function Session:_on_update(update)
  local event = events.from_update(update)

  if not event then return end

  if Session.is_state_event(event) then
    if event.kind == K.subagent then
      self.subagents:apply(event)
    else
      self.config:apply(event)
    end

    return self:_notify(event)
  end

  if event.kind == K.delegation then return end

  self:_handle(event)
end

function Session:_handle(event)
  if event.kind == K.tool_call then
    self._tools[event.id] = event.name
  elseif event.kind == K.tool_update then
    event.name = event.name or self._tools[event.id]
  elseif event.kind == K.title then
    self.title = event.title
  elseif event.kind == K.message and self._turn and not event.parent then
    self._turn.text[#self._turn.text + 1] = event.text
  end

  self:_emit(event)
end

function Session:_record_permission(tool, allowed)
  if self._turn then self._turn.permissions[#self._turn.permissions + 1] = { tool = tool, allowed = allowed } end
end

function Session:_on_request(method, params)
  if method ~= PermissionGate.METHOD then return nil end

  return self.permissions:request(params)
end

function Session:_on_close(reason)
  local running = self:running()

  self.state = Session.STATE.closed

  if not running then self:_emit(events.error(reason)) end
end

function Session:prompt(text, context, opts)
  if self:running() then error('a turn is already running in this session', 2) end
  if self.reloading then error('this session is reloading', 2) end
  if self.state == Session.STATE.closed then error('this session is closed', 2) end

  self.state = Session.STATE.running
  self._turn = { text = {}, permissions = {} }
  if not (opts and opts.shown) then self:_emit(events.prompt(text, { selections = editor_context.labels(context) })) end

  local blocks = Session.blocks_of(text, context, self.connection:prompt_capabilities())
  local instruct = self:_needs_instructions()

  if instruct then table.insert(blocks, 1, { type = 'text', text = editor_context.instructions(self.agent.system) }) end

  return async.run(function()
    local ok, result = pcall(self.connection.prompt, self.connection, self.id, blocks)

    if ok and instruct then self._instructed = true end
    local turn = self._turn

    self._turn = nil

    if self:running() then self.state = Session.STATE.idle end

    if not ok then
      self.turn_ended = Timer.now()
      self:_emit(events.error(tostring(result)))
      self:_emit(events.stop('error'))
      error(result, 0)
    end

    local reason = result and result.stopReason

    self.turn_ended = Timer.now()
    self:_emit(events.stop(reason))

    if reason ~= Connection.STOP_REASON.cancelled and self.prompts:size() > 0 then
      Timer.defer(0, function()
        self.prompts:drain()
      end)
    end

    return { stop_reason = reason, text = table.concat(turn.text, ''), permissions = turn.permissions }
  end)
end

function Session:_needs_instructions()
  local system = type(self.agent) == 'table' and self.agent.system

  return not self._instructed and type(system) == 'string' and system ~= '' and not self:can('system_prompt')
end

function Session:can(name)
  local connection = self.connection

  return type(connection) == 'table' and connection.capabilities ~= nil and connection:capabilities()[name] == true
end

function Session:idle()
  return self.state == Session.STATE.idle
end

function Session:running()
  return self.state == Session.STATE.running
end

function Session:enqueue(text, context)
  if self.state == Session.STATE.closed then error('this session is closed', 2) end

  self.prompts:enqueue(text, context)
end

function Session:steer(text, context)
  if self.state == Session.STATE.closed then error('this session is closed', 2) end

  return self.prompts:steer(text, context)
end

function Session:queued()
  return self.prompts:queued()
end

function Session:waiting()
  return self.permissions:waiting()
end

function Session:begin_load()
  self.reloading = true
end

function Session:end_load()
  if not self.reloading then return end

  self.reloading = false
  self:_notify({ kind = events.NOTICE.loaded })

  if self.prompts:size() > 0 then self.prompts:drain() end
end

function Session:begin_replay()
  self.log:begin_replay()
  self.reloading = true
end

function Session:end_replay(ok)
  local notice = self.log:end_replay(ok)

  self.reloading = false

  if notice then self:_notify({ kind = notice }) end
  if self.prompts:size() > 0 then self.prompts:drain() end

  return notice ~= nil
end

function Session:configure(result)
  self.config:configure(result)
end

function Session:option(key)
  return self.config:option(key)
end

function Session:choice(key)
  return self.config:choice(key)
end

function Session:mode()
  return self.config:mode()
end

function Session:mode_choices()
  return self.config:mode_choices()
end

function Session:set_option(id, value)
  return self.config:set_option(id, value)
end

function Session:set_mode(id)
  return self.config:set_mode(id)
end

function Session:cycle_mode()
  return self.config:cycle_mode()
end

function Session:cancel()
  local returned = self.prompts:take_all()

  if #returned > 0 then self:_notify({ kind = events.NOTICE.returned, texts = returned }) end

  if not self:running() then return returned end

  self.connection:cancel(self.id)
  self.permissions:cancel_all()

  return returned
end

function Session:close()
  if self.state == Session.STATE.closed then return end

  self.subagents:detach_all()
  self:cancel()
  self.state = Session.STATE.closed

  local connection, id = self.connection, self.id

  async.run(function()
    connection:close_session(id)
  end)
end

return Session

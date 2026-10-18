local Object = require('core.Object')
local Connection = require('harness.acp.connection')
local async = require('harness.async')
local events = require('harness.events')
local permissions = require('harness.permissions')

local Session = Object:extend()

function Session:constructor(opts)
  return {
    key = opts.key,
    id = opts.id,
    agent = opts.agent,
    dir = opts.dir,
    connection = opts.connection,
    approve = opts.approve or permissions.new(),
    parent = opts.parent,
    depth = opts.depth or 0,
    title = opts.title,
    state = 'idle',
    history = {},
    _listeners = {},
    _tools = {},
    _turn = nil,
  }
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

function Session:_emit(event)
  events.append(self.history, event)

  for _, listener in ipairs(vim.list_slice(self._listeners)) do
    local ok, err = pcall(listener.fn, event, self)

    if not ok then vim.notify('Harness: a session listener failed: ' .. tostring(err), vim.log.levels.WARN) end
  end
end

function Session:_on_update(update)
  local event = events.from_update(update)

  if not event then return end

  if event.kind == 'tool_call' then
    self._tools[event.id] = event.name
  elseif event.kind == 'tool_update' then
    event.name = event.name or self._tools[event.id]
  elseif event.kind == 'title' then
    self.title = event.title
  elseif event.kind == 'message' and self._turn then
    self._turn.text[#self._turn.text + 1] = event.text
  end

  self:_emit(event)
end

local function kind_of(decision)
  if decision == true then return 'allow_once' end
  if type(decision) ~= 'string' then return 'reject_once' end

  return decision
end

function Session:_on_request(method, params)
  if method ~= 'session/request_permission' then return nil end

  local call = params.toolCall or {}
  local tool = events.tool_name(call) or call.title or ''
  local answer = async.Future.new()

  local function decide(decision)
    local kind = kind_of(decision)
    local allowed = kind:sub(1, 5) == 'allow'

    if self._turn then self._turn.permissions[#self._turn.permissions + 1] = { tool = tool, allowed = allowed } end

    self:_emit(events.permission(tool, allowed))
    answer:set_result({ outcome = Connection.permission_outcome(params.options, kind) })
  end

  local ok, decision = pcall(self.approve, { tool = tool, params = params, session = self })

  if not ok then
    decide('reject_once')
  elseif type(decision) == 'table' and decision.on_complete then
    decision:on_complete(function(err, kind)
      decide(not err and kind or 'reject_once')
    end)
  else
    decide(decision)
  end

  return answer
end

function Session:_on_close(reason)
  local running = self.state == 'running'

  self.state = 'closed'

  if not running then self:_emit(events.error(reason)) end
end

function Session:prompt(text, context)
  if self.state == 'running' then error('a turn is already running in this session', 2) end
  if self.state == 'closed' then error('this session is closed', 2) end

  self.state = 'running'
  self._turn = { text = {}, permissions = {} }
  self:_emit(events.prompt(text))

  local blocks = { { type = 'text', text = text } }

  if context then table.insert(blocks, 1, { type = 'text', text = context }) end

  return async.run(function()
    local ok, result = pcall(self.connection.prompt, self.connection, self.id, blocks)
    local turn = self._turn

    self._turn = nil

    if self.state == 'running' then self.state = 'idle' end

    if not ok then
      self:_emit(events.error(tostring(result)))
      error(result, 0)
    end

    local reason = result and result.stopReason

    self:_emit(events.stop(reason))

    return { stop_reason = reason, text = table.concat(turn.text, ''), permissions = turn.permissions }
  end)
end

function Session:running()
  return self.state == 'running'
end

function Session:cancel()
  if self.state == 'running' then self.connection:cancel(self.id) end
end

function Session:close()
  if self.state == 'closed' then return end

  self:cancel()
  self.state = 'closed'

  local connection, id = self.connection, self.id

  async.run(function()
    connection:close_session(id)
  end)
end

return Session

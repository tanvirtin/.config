local lazy = require('core.lazy')

local fs = lazy('core.fs')
local Timer = require('core.Timer')
local console = lazy('core.console')
local Object = require('core.Object')
local async = require('harness.async')
local buffers = require('core.buffers')
local dataclass = require('core.dataclass')
local events = require('harness.types.events')
local Watch = require('harness.session.Watch')
local EditLog = require('harness.edits.EditLog')
local content = require('harness.types.content')
local editor_context = require('harness.context')
local History = require('harness.session.History')
local permissions = require('harness.permissions')
local session_types = require('harness.types.session')
local Subagents = require('harness.session.Subagents')
local PromptQueue = require('harness.session.PromptQueue')
local instructions = require('harness.types.instructions')
local SessionConfig = require('harness.session.SessionConfig')
local PermissionGate = require('harness.session.PermissionGate')
local ElicitationGate = require('harness.session.ElicitationGate')

local K = events.KIND

local Session = Object:extend()

Session.STATE = dataclass.enum({ 'idle', 'running', 'loading', 'reloading', 'closed' })

Session.TRANSITIONS = {
  idle = { running = true, loading = true, reloading = true, closed = true },
  running = { idle = true, closed = true },
  loading = { idle = true, closed = true },
  reloading = { idle = true, closed = true },
  closed = {},
}

local STATE_EVENTS = { [K.config] = true, [K.mode] = true, [K.commands] = true, [K.subagent] = true }

function Session.is_state_event(event)
  return STATE_EVENTS[event.kind] == true
end

function Session:constructor(opts)
  local session = {
    key = opts.key,
    id = opts.id,
    agent = opts.agent,
    dir = opts.dir,
    connection = opts.connection,
    approve = opts.approve or permissions.new(),
    elicit = opts.elicit,
    admit = opts.admit,
    parent = opts.parent,
    depth = opts.depth or 0,
    title = opts.title,
    state = Session.STATE.idle,
    options = {},
    commands = {},
    _listeners = {},
    _tools = {},
    _turn = nil,
    edits = EditLog(opts.file_lines or buffers.lines_of),
  }

  session.log = History()
  session.history = session.log.events
  session.times = session.log.times
  session.permissions = PermissionGate(session)
  session._pending = session.permissions.pending
  session.elicitations = ElicitationGate(session)
  session.prompts = PromptQueue(session)
  session.queue = session.prompts.items
  session.watch = Watch(session)
  session.config = SessionConfig(session)
  session.subagents = Subagents(session)
  session.children = session.subagents.children

  return session
end

function Session:attach()
  self.connection:attach(self.id, {
    event = function(event)
      self:_on_event(event)
    end,
    permission = function(request)
      return self.permissions:request(request)
    end,
    elicitation = function(request)
      return self.elicitations:request(request)
    end,
    elicitation_complete = function(id)
      self.elicitations:complete(id)
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

function Session:_on_event(event)
  if Session.is_state_event(event) then
    if event.kind == K.subagent then
      self.subagents:apply(event)
    else
      self.config:apply(event)
    end

    return self:_notify(event)
  end

  if event.kind == K.delegation then return end
  if event.kind == K.user and event.text then event.text = editor_context.strip_echoed(event.text) end

  self:_handle(event)
end

function Session:_handle(event)
  if self._loose_edits and (event.kind == K.tool_call or event.kind == K.tool_update) and event.id then
    Timer.defer(0, function()
      self:_settle_loose_edits(false)
    end)
  end

  if event.kind == K.tool_call then
    self._tools[event.id] = event.name

    if not event.parent then self.watch:open(Watch.KIND.tool, event.id, { name = event.name, title = event.title }) end
  elseif event.kind == K.tool_update then
    event.name = event.name or self._tools[event.id]

    if not event.parent and (event.status == 'completed' or event.status == 'failed') then
      self.watch:settle(Watch.KIND.tool, event.id, { status = event.status, output = event.output })
    end
  elseif event.kind == K.title then
    self.title = session_types.title(event.title) or self.title
  elseif event.kind == K.message and self._turn and not event.parent then
    self._turn.text[#self._turn.text + 1] = event.text
  end

  self:_emit(event)
end

function Session:_record_permission(tool, allowed)
  if self._turn then self._turn.permissions[#self._turn.permissions + 1] = { tool = tool, allowed = allowed } end
end

function Session:_on_close(reason)
  local running = self:running()

  self:_to(Session.STATE.closed)
  self.elicitations:cancel_all()

  if not running then self:_emit(events.error(reason)) end
end

function Session:prompt(text, context, opts)
  if self:running() then return nil, 'a turn is already running in this session' end
  if self:loading() then return nil, 'this session is loading' end
  if self.state == Session.STATE.closed then return nil, 'this session is closed' end
  if self.admit and not self.admit(self) then return nil, PromptQueue.BUSY end

  self.watch:prompted(opts)

  self:_to(Session.STATE.running)
  self._turn = { text = {}, permissions = {} }
  if not (opts and opts.shown) then
    self:_emit(events.prompt(text, { selections = content.labels(context, { skip_inline = true }) }))
  end

  local system = self:_system()
  local instruct = self:_needs_instructions(system)
  local prompt = content.prompt(text, context, instruct and system and editor_context.instructions(system) or nil)

  return async.run(function()
    local reason, err = self.connection:prompt(self.id, prompt)

    if not err and instruct then self._instructed = true end

    local turn = self._turn

    self._turn = nil

    if self:running() then self:_to(Session.STATE.idle) end

    if err then
      self.turn_ended = Timer.now()
      self:_emit(events.error(tostring(err)))
      self:_emit(events.stop('error'))
      self.watch:turn_ended('error')
      self:_return_queued(Session.RETURNED.failed)

      return nil, err
    end

    self:_settle_loose_edits(true)
    self.turn_ended = Timer.now()
    self:_emit(events.stop(reason))
    self.watch:turn_ended(reason)
    self:_look_up_title()
    self:_note_unasked()
    self:_tell_stale()

    if reason ~= events.STOP_REASON.cancelled and self.prompts:size() > 0 then
      Timer.defer(0, function()
        self.prompts:drain()
      end)
    end

    return { stop_reason = reason, text = table.concat(turn.text, ''), permissions = turn.permissions }
  end)
end

function Session:adopt_title(title)
  if self.title or type(title) ~= 'string' or title == '' then return false end

  self:_handle(events.new({ kind = K.title, title = title }))

  return true
end

function Session:_look_up_title()
  if self.title or not self:can('list') then return end

  async.run(function()
    local stored = self.connection:list_sessions(self.dir)

    for _, entry in ipairs(stored or {}) do
      if entry.id == self.id then return self:adopt_title(entry.title) end
    end
  end)
end

function Session:_active_content()
  local active = { categories = {}, names = {}, kinds = {} }
  local list = self.history or {}

  for _, event in ipairs(list) do
    active.kinds[event.kind] = true
    if event.category then active.categories[event.category] = true end
    if event.name then active.names[event.name] = true end
    if event.title then active.names[event.title] = true end
  end

  return active
end

function Session:_system()
  local system = type(self.agent) == 'table' and self.agent.system or nil

  if type(system) ~= 'string' or system == '' then return nil end

  local extra = instructions.text(self:_active_content())

  return extra ~= '' and (system .. '\n\n' .. extra) or system
end

function Session:_needs_instructions(system)
  system = system or self:_system()

  return not self._instructed and type(system) == 'string' and system ~= '' and not self:can('system_prompt')
end

function Session:can(name)
  local connection = self.connection

  return type(connection) == 'table' and connection.capabilities ~= nil and connection:capabilities()[name] == true
end

function Session:_to(state)
  if state == self.state then return self end

  if not Session.TRANSITIONS[self.state][state] then
    error(string.format('session %s cannot go from %s to %s', tostring(self.key), self.state, state), 2)
  end

  self.state = state

  return self
end

function Session:loading()
  return self.state == Session.STATE.loading or self.state == Session.STATE.reloading
end

function Session:idle()
  return self.state == Session.STATE.idle
end

function Session:running()
  return self.state == Session.STATE.running
end

Session.FINISHED = { completed = true, failed = true }

function Session:unasked_edits()
  local list = self.log.events
  local asked, edited, order = {}, {}, {}

  for i = #list, 1, -1 do
    local event = list[i]

    if event.kind == K.prompt then break end
    if event.kind == K.permission and event.id then asked[event.id] = true end

    if (event.kind == K.tool_call or event.kind == K.tool_update) and event.id and event.diffs and #event.diffs > 0 then
      if not edited[event.id] then order[#order + 1] = event.id end

      edited[event.id] = true
    end
  end

  return vim.tbl_filter(function(id)
    return not asked[id]
  end, order)
end

function Session:stale_runs()
  local list = self.log.events
  local start = 1

  for i = #list, 1, -1 do
    if list[i].kind == K.prompt then
      start = i
      break
    end
  end

  local edited, order, runs, seen = {}, {}, {}, {}

  for i = start, #list do
    local event = list[i]

    if (event.kind == K.tool_call or event.kind == K.tool_update) and event.id then
      for _, diff in ipairs(event.diffs or {}) do
        local path = editor_context.absolute(diff.path, self.dir)

        if not edited[path] then
          edited[path] = i
          order[#order + 1] = path
        end
      end

      local command = event.input and event.input.command

      if event.category == 'execute' and type(command) == 'string' and not seen[event.id] then
        seen[event.id] = true

        local stale = {}

        for _, path in ipairs(order) do
          local buffer = buffers.find(path)

          if edited[path] < i and buffer and buffer:is_modified() then stale[#stale + 1] = path end
        end

        if #stale > 0 then runs[#runs + 1] = { command = command, paths = stale } end
      end
    end
  end

  return runs
end

function Session:_tell_stale()
  local runs = self:stale_runs()

  if #runs == 0 then return end

  local run = runs[#runs]
  local names = vim.tbl_map(fs.basename, run.paths)

  console.notify(
    string.format(
      'Harness: `%s` ran while %s %s unsaved, so it saw the old text; :wa saves them',
      run.command:match('^[^\n]*'):sub(1, 60),
      table.concat(names, ', '),
      #names == 1 and 'was' or 'were'
    ),
    'warn'
  )
end

function Session:_note_unasked()
  if self.auto_edits or #self:unasked_edits() == 0 then return end

  self.auto_edits = true
  self:_notify({ kind = events.NOTICE.config })
end

function Session:_open_tool()
  local list = self.log.events
  local seen, status, diffs, order = {}, {}, {}, {}

  for i = #list, 1, -1 do
    local event = list[i]

    if (event.kind == K.tool_call or event.kind == K.tool_update) and event.id then
      if not seen[event.id] then
        seen[event.id] = true
        order[#order + 1] = event.id
      end

      if status[event.id] == nil and event.status then status[event.id] = event.status end
      if diffs[event.id] == nil and event.diffs and #event.diffs > 0 then diffs[event.id] = event.diffs end
    end

    if event.kind == K.prompt then break end
  end

  for _, id in ipairs(order) do
    if not Session.FINISHED[status[id]] then return id, diffs[id] or {} end
  end
end

function Session:_same_file(a, b)
  return a and b and editor_context.absolute(a, self.dir) == editor_context.absolute(b, self.dir)
end

function Session:_known(diffs, diff)
  for _, known in ipairs(diffs) do
    if self:_same_file(known.path, diff.path) and known.old == diff.old and known.new == diff.new then return true end
  end

  return false
end

function Session:_attach_edits(id, diffs, incoming)
  local merged = vim.deepcopy(diffs)

  for _, diff in ipairs(incoming) do
    if not self:_known(merged, diff) then merged[#merged + 1] = { path = diff.path, old = diff.old, new = diff.new } end
  end

  if #merged == #diffs then return false end

  self:_emit(events.new({ kind = K.tool_update, id = id, diffs = merged }))

  return true
end

function Session:record_edit(diff)
  if not self:running() then return false end

  local id, diffs = self:_open_tool()

  if not id then
    self._loose_edits = self._loose_edits or {}
    self._loose_edits[#self._loose_edits + 1] = diff

    return true
  end

  return self:_attach_edits(id, diffs, { diff })
end

function Session:_last_tool()
  local list = self.log.events

  for i = #list, 1, -1 do
    local event = list[i]

    if event.kind == K.prompt then return nil end
    if (event.kind == K.tool_call or event.kind == K.tool_update) and event.id then return event.id end
  end
end

function Session:_settle_loose_edits(ended)
  local loose = self._loose_edits

  if not loose or #loose == 0 then return end

  local id, diffs = self:_open_tool()

  if not id and not ended then return end

  self._loose_edits = nil

  if id then return self:_attach_edits(id, diffs, loose) end

  id = self:_last_tool()

  if id then
    local known = {}

    for i = #self.log.events, 1, -1 do
      local event = self.log.events[i]

      if event.id == id and event.diffs and #event.diffs > 0 then
        known = event.diffs
        break
      end
    end

    return self:_attach_edits(id, known, loose)
  end

  self._edit_seq = (self._edit_seq or 0) + 1
  id = 'editor-edits-' .. self._edit_seq
  self:_emit(
    events.new({ kind = K.tool_call, id = id, name = 'editor edits', category = 'edit', status = 'completed' })
  )
  self:_attach_edits(id, {}, loose)
end

function Session:enqueue(text, context, opts)
  if self.state == Session.STATE.closed then return nil, 'this session is closed' end

  self.prompts:enqueue(text, context, opts)

  return self
end

function Session:steer(text, context)
  if self.state == Session.STATE.closed then return nil, 'this session is closed' end

  return self.prompts:steer(text, context)
end

function Session:queued()
  return self.prompts:queued()
end

function Session:waiting()
  return vim.list_extend(self.permissions:waiting(), self.elicitations:waiting())
end

function Session:begin_load()
  self:_to(Session.STATE.loading)
end

function Session:end_load()
  if self.state ~= Session.STATE.loading then return end

  self:_to(Session.STATE.idle)
  self:_notify({ kind = events.NOTICE.loaded })

  if self.prompts:size() > 0 then self.prompts:drain() end
end

function Session:begin_replay()
  self.log:begin_replay()
  self:_to(Session.STATE.reloading)
end

function Session:end_replay(ok)
  local notice = self.log:end_replay(ok)

  if self.state == Session.STATE.reloading then self:_to(Session.STATE.idle) end

  if notice then self:_notify({ kind = notice }) end
  if self.prompts:size() > 0 then self.prompts:drain() end

  return notice ~= nil
end

function Session:configure(options)
  self.config:configure(options)
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

Session.RETURNED = dataclass.enum({ 'interrupted', 'failed' })

function Session:_return_queued(reason)
  local returned = self.prompts:take_all()

  if #returned > 0 then self:_notify({ kind = events.NOTICE.returned, texts = returned, reason = reason }) end

  return returned
end

function Session:cancel()
  local returned = self:_return_queued(Session.RETURNED.interrupted)

  self.elicitations:cancel_all()

  if not self:running() then return returned end

  self.connection:cancel(self.id)
  self.permissions:cancel_all()

  return returned
end

function Session:shutdown()
  if self.state == Session.STATE.closed then return self end

  self.subagents:detach_all()
  self.watch:clear()
  self:cancel()
  self:_to(Session.STATE.closed)

  return self
end

function Session:close()
  if self.state == Session.STATE.closed then return end

  self:shutdown()

  local connection, id = self.connection, self.id

  async.run(function()
    connection:close_session(id)
  end)
end

return Session

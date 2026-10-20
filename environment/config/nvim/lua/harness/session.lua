local Object = require('core.Object')
local Connection = require('harness.acp.connection')
local async = require('harness.async')
local context = require('harness.context')
local events = require('harness.events')

local K, NOTICE = events.KIND, events.NOTICE
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
    times = {},
    queue = {},
    options = {},
    modes = nil,
    commands = {},
    children = {},
    _listeners = {},
    _tools = {},
    _pending = {},
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

function Session:_notify(event)
  for _, listener in ipairs(vim.list_slice(self._listeners)) do
    local ok, err = pcall(listener.fn, event, self)

    if not ok then vim.notify('Harness: a session listener failed: ' .. tostring(err), vim.log.levels.WARN) end
  end
end

function Session:_emit(event)
  local shadow = self._shadow

  if shadow then
    events.append(shadow.history, event)
    shadow.times[#shadow.history] = shadow.times[#shadow.history] or vim.uv.now()
    return
  end

  events.append(self.history, event)
  self.times[#self.history] = self.times[#self.history] or vim.uv.now()

  for _, listener in ipairs(vim.list_slice(self._listeners)) do
    local ok, err = pcall(listener.fn, event, self)

    if not ok then vim.notify('Harness: a session listener failed: ' .. tostring(err), vim.log.levels.WARN) end
  end
end

local STATE = {
  config = function(self, event)
    self.options = event.options
  end,
  mode = function(self, event)
    if self.modes then self.modes.currentModeId = event.id end

    for _, option in ipairs(self.options) do
      if option.category == 'mode' or option.id == 'mode' then option.currentValue = event.id end
    end
  end,
  commands = function(self, event)
    self.commands = event.commands
  end,
  subagent = function(self, event)
    local child = self.children[event.child]

    if not child then
      child = { id = event.child }
      self.children[event.child] = child
      self:_follow_child(child)
    end

    for _, key in ipairs({ 'title', 'description', 'state', 'stop' }) do
      if event[key] ~= nil then child[key] = event[key] end
    end
  end,
}

function Session:_follow_child(child)
  if not (self.connection and self.connection.attach) then return end

  self.connection:attach(child.id, {
    update = function(update)
      self:_on_child_update(child, update)
    end,
    request = function(method, params)
      return self:_on_request(method, params)
    end,
  })
end

function Session:_on_child_update(child, update)
  local event = events.from_update(update)

  if not event or STATE[event.kind] then return end

  if event.kind == K.delegation then
    child.tool = event.message or child.tool
    return self:_notify({ kind = K.subagent })
  end

  event.parent = event.parent or child.tool
  child.tool = child.tool or event.parent

  self:_handle(event)
end

function Session:configure(result)
  if type(result) ~= 'table' then return end

  if type(result.configOptions) == 'table' then self.options = result.configOptions end
  if type(result.modes) == 'table' then self.modes = result.modes end

  self:_notify({ kind = NOTICE.config })
end

local function find_option(options, key)
  for _, option in ipairs(options) do
    if option.id == key then return option end
  end

  for _, option in ipairs(options) do
    if option.category == key then return option end
  end
end

function Session:option(key)
  return find_option(self.options, key)
end

local function choices(option)
  local out = {}

  for _, choice in ipairs(option.options or {}) do
    if type(choice) == 'table' and choice.options then
      vim.list_extend(out, choice.options)
    else
      out[#out + 1] = choice
    end
  end

  return out
end

Session.choices = choices

function Session:choice(key)
  local option = self:option(key)

  if not option then return nil end

  for _, choice in ipairs(choices(option)) do
    if choice.value == option.currentValue then return choice end
  end
end

function Session:mode()
  local choice = self:choice('mode')

  if choice then return { id = choice.value, name = choice.name } end

  local modes = self.modes

  if not modes then return nil end

  for _, mode in ipairs(modes.availableModes or {}) do
    if mode.id == modes.currentModeId then return { id = mode.id, name = mode.name } end
  end
end

function Session:mode_choices()
  local option = self:option('mode')

  if option then
    return vim.tbl_map(function(choice)
      return { id = choice.value, name = choice.name, description = choice.description }
    end, choices(option))
  end

  return vim.tbl_map(function(mode)
    return { id = mode.id, name = mode.name, description = mode.description }
  end, (self.modes or {}).availableModes or {})
end

function Session:set_option(id, value)
  return async.run(function()
    local result = self.connection:set_config(self.id, id, value)

    if type(result) == 'table' and type(result.configOptions) == 'table' and #result.configOptions > 0 then
      self.options = result.configOptions
    else
      local option = find_option(self.options, id)
      if option then option.currentValue = value end
    end

    self:_notify({ kind = NOTICE.config })

    return result
  end)
end

function Session:set_mode(id)
  local option = self:option('mode')

  if option then return self:set_option(option.id, id) end

  return async.run(function()
    local result = self.connection:set_mode(self.id, id)

    if self.modes then self.modes.currentModeId = id end
    self:_notify({ kind = NOTICE.config })

    return result
  end)
end

function Session:cycle_mode()
  local available = self:mode_choices()
  local current = self:mode()

  if #available == 0 then return nil end

  local index = 0

  for i, mode in ipairs(available) do
    if current and mode.id == current.id then index = i end
  end

  return self:set_mode(available[index % #available + 1].id)
end

function Session:_on_update(update)
  local event = events.from_update(update)

  if not event then return end

  if STATE[event.kind] then
    STATE[event.kind](self, event)
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

local function kind_of(decision)
  if decision == true then return Connection.DECISION.allow_once end
  if type(decision) ~= 'string' then return Connection.DECISION.reject_once end

  return decision
end

function Session:_on_request(method, params)
  if method ~= 'session/request_permission' then return nil end

  local call = params.toolCall or {}
  local tool = events.tool_name(call) or call.title or ''
  local answer = async.Future.new()
  local pending = { tool = tool, answer = answer, id = call.toolCallId, title = call.title }

  local function decide(decision)
    if answer.done then return end

    self._pending[pending] = nil
    self:_notify({ kind = NOTICE.waiting })

    local kind = kind_of(decision)
    local allowed = kind:sub(1, 5) == 'allow'

    if self._turn then self._turn.permissions[#self._turn.permissions + 1] = { tool = tool, allowed = allowed } end

    self:_emit(events.permission(tool, allowed))
    answer:set_result({ outcome = Connection.permission_outcome(params.options, kind) })
  end

  self._pending[pending] = true
  self:_notify({ kind = NOTICE.waiting })

  local ok, decision = pcall(self.approve, { tool = tool, params = params, session = self })

  if not ok then
    decide(Connection.DECISION.reject_once)
  elseif type(decision) == 'table' and decision.on_complete then
    pending.dismiss = decision.dismiss
    decision:on_complete(function(err, kind)
      decide(not err and kind or Connection.DECISION.reject_once)
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

local function blocks_of(text, context)
  local blocks = { { type = 'text', text = text } }

  if context then table.insert(blocks, 1, { type = 'text', text = context }) end

  return blocks
end

function Session:prompt(text, context, opts)
  if self.state == 'running' then error('a turn is already running in this session', 2) end
  if self.reloading then error('this session is reloading', 2) end
  if self.state == 'closed' then error('this session is closed', 2) end

  self.state = 'running'
  self._turn = { text = {}, permissions = {} }
  if not (opts and opts.shown) then self:_emit(events.prompt(text)) end

  local blocks = blocks_of(text, context)

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

    self.turn_ended = vim.uv.now()
    self:_emit(events.stop(reason))

    if reason ~= Connection.STOP_REASON.cancelled and #self.queue > 0 then
      vim.schedule(function()
        self:_drain()
      end)
    end

    return { stop_reason = reason, text = table.concat(turn.text, ''), permissions = turn.permissions }
  end)
end

function Session:_drain()
  if self.state ~= 'idle' or self.reloading or #self.queue == 0 then return end

  local next = table.remove(self.queue, 1)

  self:_notify({ kind = NOTICE.queue })

  local ok, err = pcall(self.prompt, self, next.text, next.context, { shown = next.shown })

  if not ok then
    table.insert(self.queue, 1, next)
    self:_notify({ kind = NOTICE.queue })
    vim.notify('Harness: could not send the queued message: ' .. tostring(err), vim.log.levels.WARN)
  end
end

function Session:enqueue(text, context)
  if self.state == 'closed' then error('this session is closed', 2) end

  self.queue[#self.queue + 1] = { text = text, context = context }
  self:_notify({ kind = NOTICE.queue })

  if self.state == 'idle' then self:_drain() end
end

function Session:steer(text, context)
  if self.state == 'closed' then error('this session is closed', 2) end

  if self.state ~= 'running' or not self.connection:steering() then return self:enqueue(text, context) end

  self:_emit(events.prompt(text, { steered = true }))

  local steered = self.history[#self.history]

  local blocks = blocks_of(text, context)

  return async.run(function()
    local result = self.connection:steer(self.id, blocks)

    if type(result) == 'table' and result.outcome == 'promptRequired' then
      steered.steered = nil
      self:_notify({ kind = NOTICE.reset })

      if self.state == 'running' then
        self.queue[#self.queue + 1] = { text = text, context = context, shown = true }
        self:_notify({ kind = NOTICE.queue })
      else
        self:prompt(text, context, { shown = true })
      end
    end

    return result
  end)
end

function Session:begin_replay()
  self._shadow = { history = {}, times = {} }
  self.reloading = true
end

local USER = { prompt = true, user = true }

local function prompts(history)
  local out = {}

  for i, event in ipairs(history) do
    if USER[event.kind] then out[#out + 1] = { index = i, text = vim.trim(context.strip(event.text or '')) } end
  end

  return out
end

local LOCAL = { stop = true, permission = true, error = true }

local function compare(ours, theirs)
  for i = 1, math.min(#ours, #theirs) do
    if theirs[i].text ~= ours[i].text then return 'diverged' end
  end

  return #theirs < #ours and 'behind' or 'extends'
end

local function refreshable(history, from)
  if history[from].kind ~= K.user then return false end

  for i = from + 1, #history do
    if LOCAL[history[i].kind] then return false end
  end

  return true
end

function Session:_adopt(shadow)
  local ours, theirs = prompts(self.history), prompts(shadow.history)

  local relation = compare(ours, theirs)

  if relation == 'behind' then return false end

  if relation == 'extends' then
    local last = ours[#ours]
    local from, source

    if last and refreshable(self.history, last.index) then
      from, source = last.index, theirs[#ours].index
    elseif #theirs > #ours then
      from, source = #self.history + 1, theirs[#ours + 1].index
    else
      return false
    end

    local tail = vim.list_slice(shadow.history, source)

    if vim.deep_equal(tail, vim.list_slice(self.history, from)) then return false end

    local now = vim.uv.now()

    for i = #self.history, from, -1 do
      self.history[i] = nil
    end

    for offset, event in ipairs(tail) do
      local index = from + offset - 1

      self.history[index] = event
      self.times[index] = self.times[index] or now
    end

    for i = #self.history + 1, #self.times do
      self.times[i] = nil
    end

    self:_notify({ kind = NOTICE.appended })

    return true
  end

  local before = #self.history

  for i = 1, math.min(before, #shadow.history) do
    shadow.times[i] = self.times[i] or shadow.times[i]
  end

  self.history, self.times = shadow.history, shadow.times
  self:_notify({ kind = NOTICE.reset })

  return true
end

function Session:end_replay(ok)
  local shadow = self._shadow

  self._shadow = nil
  self.reloading = false

  local changed = ok and shadow and self:_adopt(shadow) or false

  if #self.queue > 0 then self:_drain() end

  return changed
end

function Session:waiting()
  local out = {}

  for pending in pairs(self._pending) do
    out[#out + 1] = { tool = pending.tool, id = pending.id, title = pending.title }
  end

  return out
end

function Session:queued()
  return vim.tbl_map(function(item)
    return item.text
  end, self.queue)
end

function Session:running()
  return self.state == 'running'
end

function Session:cancel()
  local returned = self:queued()

  self.queue = {}
  if #returned > 0 then self:_notify({ kind = NOTICE.queue }) end

  if self.state ~= 'running' then return returned end

  self.connection:cancel(self.id)

  for pending in pairs(self._pending) do
    self._pending[pending] = nil
    if pending.dismiss then pcall(pending.dismiss) end
    self:_emit(events.permission(pending.tool, false))
    pending.answer:set_result({ outcome = Connection.permission_outcome(nil, 'cancelled') })
  end

  async.drain()

  return returned
end

function Session:close()
  if self.state == 'closed' then return end

  for id in pairs(self.children) do
    if self.connection.detach then self.connection:detach(id) end
  end

  self:cancel()
  self.state = 'closed'

  local connection, id = self.connection, self.id

  async.run(function()
    connection:close_session(id)
  end)
end

return Session

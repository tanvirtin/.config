local Object = require('core.Object')
local console = require('core.console')
local capabilities = require('harness.types.capabilities')
local acp_config = require('harness.servers.acp.config')
local translate = require('harness.servers.acp.translate')
local updates = require('harness.servers.acp.updates')
local async = require('harness.async')
local jsonrpc = require('harness.servers.acp.jsonrpc')

local Connection = Object:extend()

Connection.PROTOCOL_VERSION = 1

Connection.CLIENT_INFO = { name = 'harness', title = 'Neovim harness', version = '0.1.0' }

Connection.AUTH_REQUIRED = -32000

function Connection:constructor(transport)
  local conn = {
    _transport = transport,
    _next_id = 0,
    _pending = {},
    _listeners = {},
    _early = {},
    closed = false,
    agent_capabilities = {},
  }

  transport:on_message(function(message)
    Connection._dispatch(conn, message)
  end)

  transport:on_close(function(out)
    Connection._closed(conn, out)
  end)

  return conn
end

function Connection:capabilities()
  local prompt = self:prompt_capabilities()

  return capabilities.new({
    load = self:can_load(),
    resume = self:supports('resume'),
    fork = self:supports('fork'),
    fork_at_message = self:supports('fork') and self.fork_at_message == true,
    list = self:supports('list'),
    close = self:supports('close'),
    delete = self:supports('delete'),
    steer = self:steering(),
    system_prompt = self:supports('systemPrompt'),
    embedded_context = prompt.embeddedContext == true,
    images = prompt.image == true,
    audio = prompt.audio == true,
  })
end

function Connection:prompt_capabilities()
  return self.agent_capabilities.promptCapabilities or {}
end

function Connection:_closed(out)
  local reason = 'agent exited' .. (out and out.code and (' with code ' .. out.code) or '')
  local stderr = vim.trim(table.concat(self._transport.stderr or {}))

  if stderr ~= '' then reason = reason .. ': ' .. stderr:sub(-500) end

  self.closed = true

  for id, future in pairs(self._pending) do
    self._pending[id] = nil
    future:set_exception(reason)
  end

  for _, listener in pairs(self._listeners) do
    if listener.close then listener.close(reason) end
  end

  async.drain()
end

function Connection:request(method, params)
  if self.closed then
    local future = async.Future.new()
    future:set_exception('agent is not running')
    return future
  end

  self._next_id = self._next_id + 1

  local future = async.Future.new()
  self._pending[self._next_id] = future
  self._transport:send(jsonrpc.request(self._next_id, method, params))

  return future
end

function Connection:notify(method, params)
  if not self.closed then self._transport:send(jsonrpc.notification(method, params)) end
end

Connection.PERMISSION_METHOD = 'session/request_permission'

local function deliver(delegate, update)
  local event = updates.from_update(update)

  if event and delegate.event then delegate.event(event) end
end

function Connection:attach(session_id, delegate)
  self._listeners[session_id] = delegate

  local early = self._early[session_id] or {}
  self._early[session_id] = nil

  for _, update in ipairs(early) do
    deliver(delegate, update)
  end
end

function Connection:detach(session_id)
  self._listeners[session_id] = nil
end

function Connection:_dispatch(message)
  if jsonrpc.is_response(message) then
    local future = self._pending[message.id]

    if not future then return end

    self._pending[message.id] = nil

    if message.error then
      future:set_exception(self:_failure(message.error))
    else
      future:set_result(message.result)
    end

    async.drain()
  elseif jsonrpc.is_request(message) then
    self:_on_request(message)
  elseif message.method == 'session/update' then
    local params = message.params or {}
    local listener = self._listeners[params.sessionId]

    if listener then
      deliver(listener, params.update or {})
    elseif params.sessionId then
      local early = self._early[params.sessionId] or {}
      early[#early + 1] = params.update or {}
      self._early[params.sessionId] = early
    end
  end
end

function Connection:_on_request(message)
  local params = message.params or {}
  local listener = self._listeners[params.sessionId]

  local function reply(ok, result)
    if self.closed then return end

    if ok then
      self._transport:send(jsonrpc.result(message.id, result))
    else
      self._transport:send(jsonrpc.error(message.id, jsonrpc.INTERNAL_ERROR, tostring(result)))
    end
  end

  if message.method ~= Connection.PERMISSION_METHOD or not (listener and listener.permission) then
    self._transport:send(
      jsonrpc.error(message.id, jsonrpc.METHOD_NOT_FOUND, 'not supported by the Neovim client: ' .. message.method)
    )
    return
  end

  local function answer(kind)
    return { outcome = Connection.permission_outcome(params.options, kind) }
  end

  local ok, result = pcall(listener.permission, translate.permission_request(params))

  if ok and type(result) == 'table' and result.on_complete then
    result:on_complete(function(err, value)
      reply(not err, err or answer(value))
    end)
    async.drain()
    return
  end

  reply(ok, ok and answer(result) or result)
end

Connection.DECISION = require('harness.types.permission').DECISION

Connection.STOP_REASON = require('harness.types.events').STOP_REASON

function Connection.permission_outcome(options, kind)
  if kind == true then kind = Connection.DECISION.allow_once end
  if type(kind) ~= 'string' or kind == Connection.DECISION.cancelled then return { outcome = 'cancelled' } end

  local family = kind:match('^(%a+)_') or kind

  local function find(matches)
    for _, option in ipairs(options or {}) do
      if type(option.kind) == 'string' and matches(option.kind) then return option end
    end
  end

  local chosen = find(function(option_kind)
    return option_kind == kind
  end) or find(function(option_kind)
    return option_kind:sub(1, #family) == family
  end)

  if not chosen then return { outcome = 'cancelled' } end

  return { outcome = 'selected', optionId = chosen.optionId }
end

function Connection:_failure(err)
  local text = type(err.message) == 'string' and err.message or vim.inspect(err)
  local auth = err.code == Connection.AUTH_REQUIRED or text:lower():find('authentication required', 1, true)

  if not auth then return text end

  local steps = {}

  for _, method in ipairs(self.auth_methods or {}) do
    if type(method) == 'table' then steps[#steps + 1] = method.description or method.name or method.id end
  end

  if #steps == 0 and self.login then steps[1] = self.login end

  local agent = type(self.info) == 'table' and (self.info.title or self.info.name) or 'the agent'

  if #steps == 0 then return string.format('%s needs you to sign in: %s', agent, text) end

  return string.format('%s needs you to sign in: %s, then send again (%s)', agent, table.concat(steps, '; or '), text)
end

function Connection:initialize()
  local result = async.await(self:request('initialize', {
    protocolVersion = Connection.PROTOCOL_VERSION,
    clientInfo = Connection.CLIENT_INFO,
    clientCapabilities = { subagents = vim.empty_dict() },
  }))

  self.agent_capabilities = (result and result.agentCapabilities) or {}
  self.info = result and result.agentInfo
  self.auth_methods = type(result) == 'table' and result.authMethods or {}
  self.extensions = type(result) == 'table' and type(result._meta) == 'table' and result._meta or {}

  local version = type(result) == 'table' and result.protocolVersion

  if version and version ~= Connection.PROTOCOL_VERSION then
    console.warn(
      string.format(
        'Harness: the agent speaks ACP version %s; this client speaks %d',
        tostring(version),
        Connection.PROTOCOL_VERSION
      )
    )
  end

  return result
end

function Connection:session_params(opts)
  local params = { cwd = opts.cwd, mcpServers = opts.mcp_servers or {} }

  if opts.system_prompt and self:supports('systemPrompt') then
    params.systemPrompt = { mode = 'append', content = { { type = 'text', text = opts.system_prompt } } }
  end

  return params
end

function Connection:new_session(opts)
  return acp_config.opened(async.await(self:request('session/new', self:session_params(opts))))
end

function Connection:can_load()
  return self.agent_capabilities.loadSession == true
end

function Connection:load_session(session_id, opts)
  if not self:can_load() then error('this agent cannot load stored sessions', 0) end

  local params = self:session_params(opts)
  params.sessionId = session_id

  return acp_config.opened(async.await(self:request('session/load', params)))
end

function Connection:list_sessions(cwd)
  local sessions, cursor, seen = {}, nil, {}

  repeat
    local result = async.await(self:request('session/list', { cwd = cwd, cursor = cursor })) or {}
    local page = result.sessions or {}

    for _, entry in ipairs(page) do
      if type(entry) == 'table' and type(entry.sessionId) == 'string' then
        sessions[#sessions + 1] = acp_config.stored(entry)
      end
    end

    seen[cursor or ''] = true
    cursor = result.nextCursor

    if #page == 0 or (cursor and seen[cursor]) then cursor = nil end
  until not cursor

  return sessions
end

function Connection.fork_point(message_id)
  return { jetbrains = { air = { fork = { version = 1, messageId = message_id } } } }
end

function Connection:can_fork()
  return self:supports('fork')
end

function Connection:fork_session(session_id, opts)
  if not self:can_fork() then error('this agent cannot fork sessions', 0) end

  local params = self:session_params(opts)

  params.sessionId = session_id

  if opts.message_id and self.fork_at_message then params._meta = Connection.fork_point(opts.message_id) end

  return acp_config.opened(async.await(self:request('session/fork', params)))
end

function Connection:prompt(session_id, prompt)
  local blocks = translate.prompt(prompt, self:prompt_capabilities())

  local result = async.await(self:request('session/prompt', { sessionId = session_id, prompt = blocks }))

  return type(result) == 'table' and result.stopReason or nil
end

function Connection:set_config(session_id, config_id, value)
  return async.await(self:request('session/set_config_option', {
    sessionId = session_id,
    configId = config_id,
    value = value,
  }))
end

function Connection:set_model(session_id, model_id)
  return async.await(self:request('session/set_model', { sessionId = session_id, modelId = model_id }))
end

function Connection:set_mode(session_id, mode_id)
  return async.await(self:request('session/set_mode', { sessionId = session_id, modeId = mode_id }))
end

function Connection:set_option(session_id, option_id, value)
  if option_id == acp_config.MODES then
    self:set_mode(session_id, value)
    return nil
  end

  local result = self:set_config(session_id, option_id, value)
  local options = type(result) == 'table' and acp_config.options(result.configOptions) or {}

  return #options > 0 and options or nil
end

function Connection:use_model(session_id, model)
  local ok, options = pcall(self.set_option, self, session_id, 'model', model)

  if ok then return options end

  local fallback, why = pcall(self.set_model, self, session_id, model)

  if not fallback then
    console.warn(string.format('Harness: could not use model %s: %s', model, tostring(why or options)))
  end

  return nil
end

function Connection:cancel(session_id)
  self:notify('session/cancel', { sessionId = session_id })
end

Connection.STEER_METHOD = '_session/steering'

function Connection:steering()
  local steering = (self.extensions or {}).steering

  return type(steering) == 'table' and steering.supported == true
end

function Connection:steer(session_id, prompt)
  return async.await(self:request(Connection.STEER_METHOD, {
    sessionId = session_id,
    prompt = translate.prompt(prompt, self:prompt_capabilities()),
    _meta = { steering = { idleBehavior = 'promptRequired' } },
  }))
end

function Connection:supports(capability)
  return type((self.agent_capabilities.sessionCapabilities or {})[capability]) == 'table'
end

function Connection:close_session(session_id)
  self:detach(session_id)

  if self:supports('close') then pcall(async.await, self:request('session/close', { sessionId = session_id })) end
end

function Connection:delete_session(session_id)
  self:detach(session_id)

  if not self:supports('delete') then error('this agent cannot delete sessions', 0) end

  return async.await(self:request('session/delete', { sessionId = session_id }))
end

function Connection:close()
  self.closed = true
  self._transport:close()
end

return Connection

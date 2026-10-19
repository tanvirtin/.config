local Object = require('core.Object')
local async = require('harness.async')
local jsonrpc = require('harness.acp.jsonrpc')

local Connection = Object:extend()

Connection.PROTOCOL_VERSION = 1

function Connection:constructor(transport)
  local conn = {
    _transport = transport,
    _next_id = 0,
    _pending = {},
    _listeners = {},
    _early = {},
    closed = false,
    capabilities = {},
  }

  transport:on_message(function(message)
    Connection._dispatch(conn, message)
  end)

  transport:on_close(function(out)
    Connection._closed(conn, out)
  end)

  return conn
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

function Connection:attach(session_id, listener)
  self._listeners[session_id] = listener

  local early = self._early[session_id] or {}
  self._early[session_id] = nil

  for _, update in ipairs(early) do
    listener.update(update)
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
      future:set_exception(message.error.message or vim.inspect(message.error))
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
      listener.update(params.update or {})
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

  if not (listener and listener.request) then
    self._transport:send(
      jsonrpc.error(message.id, jsonrpc.METHOD_NOT_FOUND, 'not supported by the Neovim client: ' .. message.method)
    )
    return
  end

  local ok, result = pcall(listener.request, message.method, params)

  if ok and result == nil then
    self._transport:send(
      jsonrpc.error(message.id, jsonrpc.METHOD_NOT_FOUND, 'not supported by the Neovim client: ' .. message.method)
    )
    return
  end

  if ok and type(result) == 'table' and result.on_complete then
    result:on_complete(function(err, value)
      reply(not err, err or value)
    end)
    async.drain()
    return
  end

  reply(ok, result)
end

function Connection.permission_outcome(options, kind)
  if kind == true then kind = 'allow_once' end
  if type(kind) ~= 'string' or kind == 'cancelled' then return { outcome = 'cancelled' } end

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

function Connection:initialize()
  local result = async.await(self:request('initialize', {
    protocolVersion = Connection.PROTOCOL_VERSION,
    clientCapabilities = vim.empty_dict(),
  }))

  self.capabilities = (result and result.agentCapabilities) or {}
  self.info = result and result.agentInfo
  self.extensions = type(result) == 'table' and type(result._meta) == 'table' and result._meta or {}

  return result
end

local function session_params(opts)
  local params = { cwd = opts.cwd, mcpServers = opts.mcp_servers or {} }

  if opts.system_prompt then
    params.systemPrompt = { mode = 'append', content = { { type = 'text', text = opts.system_prompt } } }
  end

  return params
end

function Connection:new_session(opts)
  return async.await(self:request('session/new', session_params(opts)))
end

function Connection:load_session(session_id, opts)
  local params = session_params(opts)
  params.sessionId = session_id

  return async.await(self:request('session/load', params))
end

function Connection:list_sessions(cwd)
  local sessions, cursor = {}, nil

  repeat
    local result = async.await(self:request('session/list', { cwd = cwd, cursor = cursor })) or {}

    vim.list_extend(sessions, result.sessions or {})
    cursor = result.nextCursor
  until not cursor or #sessions >= 200

  return sessions
end

function Connection:prompt(session_id, blocks)
  return async.await(self:request('session/prompt', { sessionId = session_id, prompt = blocks }))
end

function Connection:set_config(session_id, config_id, value)
  return async.await(self:request('session/set_config_option', {
    sessionId = session_id,
    configId = config_id,
    value = value,
  }))
end

function Connection:cancel(session_id)
  self:notify('session/cancel', { sessionId = session_id })
end

Connection.STEER_METHOD = '_session/steering'

function Connection:steering()
  local steering = (self.extensions or {}).steering

  return type(steering) == 'table' and steering.supported == true
end

function Connection:steer(session_id, blocks)
  return async.await(self:request(Connection.STEER_METHOD, {
    sessionId = session_id,
    prompt = blocks,
    _meta = { steering = { idleBehavior = 'promptRequired' } },
  }))
end

function Connection:supports(capability)
  return type((self.capabilities.sessionCapabilities or {})[capability]) == 'table'
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

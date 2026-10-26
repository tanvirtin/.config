local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local Session = lazy('harness.Session')
local servers = lazy('harness.servers')

local Workspace = Object:extend()

function Workspace:constructor(dir, opts)
  return { dir = dir, sessions = {}, _connections = {}, _opts = opts or {} }
end

function Workspace:connection(agent)
  local existing = self._connections[agent.name]
  local usable = existing and not (existing.done and (existing.err or existing.result.closed))

  if usable then return async.await(existing) end

  local future = async.Future()

  self._connections[agent.name] = future

  local server, err = servers.get(agent.server)
  local connection

  if not err then
    connection, err = server.connect(agent, self.dir, { spawn = self._opts.spawn })
  end
  if err then
    future:set_exception(err)
    return nil, err
  end

  future:set_result(connection)

  return connection
end

function Workspace:_use_model(connection, agent, id)
  return agent.model and connection:use_model(id, agent.model) or nil
end

function Workspace:_configure(session, opened, options)
  session:configure(opened and opened.options)
  session:configure(options)

  return self
end

function Workspace:_tool_servers(agent, key)
  return self._opts.servers and self._opts.servers(agent, key) or agent:mcp_servers()
end

function Workspace:_session_opts(agent, key)
  return { cwd = self.dir, mcp_servers = self:_tool_servers(agent, key), system_prompt = agent and agent.system }
end

function Workspace:new_session(agent, opts)
  local connection, err = self:connection(agent)

  if err then return nil, err end

  local opened, open_err = connection:new_session(self:_session_opts(agent, opts.key))

  if open_err then return nil, open_err end

  local model = self:_use_model(connection, agent, opened.id)
  local session = Session(vim.tbl_extend('force', opts, {
    id = opened.id,
    agent = agent,
    dir = self.dir,
    connection = connection,
  })):attach()

  self:_configure(session, opened, model)
  self.sessions[opts.key] = session

  return session
end

function Workspace:load_session(agent, id, opts)
  local connection, err = self:connection(agent)

  if err then return nil, err end

  local session = Session(vim.tbl_extend('force', opts, {
    id = id,
    agent = agent,
    dir = self.dir,
    connection = connection,
  })):attach()

  self.sessions[opts.key] = session

  if opts.on_session then
    session:begin_load()
    opts.on_session(session)
  end

  local loaded, load_err = connection:load_session(id, self:_session_opts(agent, opts.key))

  if load_err then
    self.sessions[opts.key] = nil
    return nil, load_err
  end

  self:_configure(session, loaded, self:_use_model(connection, agent, id))
  session:end_load()

  return session
end

function Workspace:fork(session, message_id, opts)
  local agent = session.agent
  local params = vim.tbl_extend('force', self:_session_opts(agent, opts.key), { message_id = message_id })
  local forked, err = session.connection:fork_session(session.id, params)

  if err then return nil, err end

  return self:load_session(agent, forked.id, opts)
end

function Workspace:reload(session)
  if not session:idle() then return false end

  session:begin_replay()

  local _, err = session.connection:load_session(session.id, self:_session_opts(session.agent, session.key))
  local changed = session:end_replay(err == nil)

  if err then return nil, err end

  return changed
end

function Workspace:find(id)
  for _, session in pairs(self.sessions) do
    if session.id == id then return session end
  end
end

function Workspace:list(agent)
  local out, seen = {}, {}

  for _, session in pairs(self.sessions) do
    if session.agent.name == agent.name and session.state ~= 'closed' then
      seen[session.id] = true
      out[#out + 1] = { id = session.id, title = session.title, session = session }
    end
  end

  local connection, err = self:connection(agent)

  if err then return nil, err end

  if connection:capabilities().list then
    local stored_sessions, list_err = connection:list_sessions(self.dir)

    if list_err then return nil, list_err end

    for _, stored in ipairs(stored_sessions) do
      if not seen[stored.id] then
        out[#out + 1] = { id = stored.id, title = stored.title, updated_at = stored.updated_at }
      end
    end
  end

  return out
end

function Workspace:delete(agent, id)
  local live = self:find(id)

  if live then
    live:shutdown()
    self.sessions[live.key] = nil
  end

  local connection, err = self:connection(agent)

  if err then return nil, err end

  return connection:delete_session(id)
end

function Workspace:forget(key)
  self.sessions[key] = nil
end

function Workspace:close()
  for _, session in pairs(self.sessions) do
    session:shutdown()
  end

  for _, future in pairs(self._connections) do
    if future.done and not future.err then future.result:close() end
  end

  self.sessions, self._connections = {}, {}
end

return Workspace

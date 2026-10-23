local Object = require('core.Object')
local servers = require('harness.servers')
local Session = require('harness.session')
local async = require('harness.async')

local Workspace = Object:extend()

function Workspace:constructor(dir, opts)
  return { dir = dir, sessions = {}, _connections = {}, _opts = opts or {} }
end

function Workspace:connection(agent)
  local existing = self._connections[agent.name]
  local usable = existing and not (existing.done and (existing.err or existing.result.closed))

  if usable then return async.await(existing) end

  local future = async.Future.new()
  self._connections[agent.name] = future

  local ok, connection = pcall(function()
    return servers.get(agent.server).connect(agent, self.dir, { spawn = self._opts.spawn })
  end)

  if ok then
    future:set_result(connection)
  else
    future:set_exception(connection)
    error(connection, 0)
  end

  return connection
end

local function use_model(connection, agent, id)
  return agent.model and connection:use_model(id, agent.model) or nil
end

local function configure(session, opened, options)
  session:configure(opened and opened.options)
  session:configure(options)
end

local function tool_servers(self, agent, key)
  return self._opts.servers and self._opts.servers(agent, key) or agent:mcp_servers()
end

function Workspace:new_session(agent, opts)
  local connection = self:connection(agent)
  local result = connection:new_session({
    cwd = self.dir,
    mcp_servers = tool_servers(self, agent, opts.key),
    system_prompt = agent.system,
  })

  local model = use_model(connection, agent, result.id)

  local session = Session(vim.tbl_extend('force', opts, {
    id = result.id,
    agent = agent,
    dir = self.dir,
    connection = connection,
  })):attach()

  configure(session, result, model)

  self.sessions[opts.key] = session

  return session
end

function Workspace:load_session(agent, id, opts)
  local connection = self:connection(agent)
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

  local ok, loaded = pcall(connection.load_session, connection, id, {
    cwd = self.dir,
    mcp_servers = tool_servers(self, agent, opts.key),
    system_prompt = agent.system,
  })

  if not ok then
    self.sessions[opts.key] = nil
    error(loaded, 0)
  end

  configure(session, loaded, use_model(connection, agent, id))
  session:end_load()

  return session
end

function Workspace:fork(session, message_id, opts)
  local agent = session.agent
  local forked = session.connection:fork_session(session.id, {
    cwd = self.dir,
    mcp_servers = tool_servers(self, agent, opts.key),
    system_prompt = agent and agent.system,
    message_id = message_id,
  })

  return self:load_session(agent, forked.id, opts)
end

function Workspace:reload(session)
  if session.state ~= 'idle' or session.reloading then return false end

  session:begin_replay()

  local ok, err = pcall(session.connection.load_session, session.connection, session.id, {
    cwd = self.dir,
    mcp_servers = tool_servers(self, session.agent, session.key),
    system_prompt = session.agent and session.agent.system,
  })

  local changed = session:end_replay(ok)

  if not ok then error(err, 0) end

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

  local connection = self:connection(agent)

  if connection:capabilities().list then
    for _, stored in ipairs(connection:list_sessions(self.dir)) do
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
    live:cancel()
    live.state = 'closed'
    self.sessions[live.key] = nil
  end

  self:connection(agent):delete_session(id)
end

function Workspace:forget(key)
  self.sessions[key] = nil
end

function Workspace:close()
  for _, session in pairs(self.sessions) do
    session.state = 'closed'
  end

  for _, future in pairs(self._connections) do
    if future.done and not future.err then future.result:close() end
  end

  self.sessions, self._connections = {}, {}
end

return Workspace

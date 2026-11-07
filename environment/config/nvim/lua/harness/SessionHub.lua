local lazy = require('core.lazy')

local fs = lazy('core.fs')
local env = lazy('core.env')
local Object = lazy('core.Object')
local agent = lazy('harness.agent')
local async = lazy('harness.async')
local Session = lazy('harness.Session')
local Workspace = lazy('harness.Workspace')
local Admission = lazy('harness.Admission')
local permissions = lazy('harness.permissions')
local session_store = require('harness.session_store')

local SessionHub = Object:extend()

SessionHub.DEFAULTS = {
  agent = nil,
  auto_allow = nil,
  max_running = 4,
  max_depth = 2,
  ask = nil,
  elicit = nil,
  spawn = nil,
}

local function lua_root()
  local source = debug.getinfo(1, 'S').source:sub(2)

  return fs.normalize(fs.dirname(source) .. '/..')
end

function SessionHub:constructor(store)
  local hub = {
    config = vim.deepcopy(SessionHub.DEFAULTS),
    store = store or session_store,
    workspaces = {},
    _starting = {},
    _hidden = {},
    _next_key = 0,
  }

  hub.admission = Admission({
    store = hub.store,
    limit = function()
      return hub.config.max_running
    end,
  })
  hub._admit = function(session)
    return hub.admission:allows(session)
  end

  return hub
end

function SessionHub:register_events()
  self.admission:register_events()

  return self
end

function SessionHub:configure(overrides)
  self.config = vim.tbl_extend('force', self.config, overrides)

  return self
end

function SessionHub:dir()
  return fs.cwd()
end

function SessionHub:editor_server(key)
  return {
    name = permissions.MCP_NAME,
    command = env.progpath(),
    args = { '--headless', '-u', 'NONE', '-l', lua_root() .. '/nvim_mcp/run.lua', env.server_address() },
    env = { { name = 'HARNESS_SESSION', value = key or '' } },
  }
end

function SessionHub:workspace(dir)
  dir = dir or self:dir()

  if not self.workspaces[dir] then
    self.workspaces[dir] = Workspace(dir, {
      spawn = function(a, d)
        return self.config.spawn and self.config.spawn(a, d) or nil
      end,
      servers = function(a, key)
        if a.editor == false then return a:mcp_servers() end

        return vim.list_extend({ self:editor_server(key) }, a:mcp_servers())
      end,
    })
  end

  return self.workspaces[dir]
end

function SessionHub:admit(session)
  return self.admission:allows(session)
end

function SessionHub:running()
  return self.admission:running()
end

function SessionHub:admit_waiting()
  self.admission:release()
end

function SessionHub:_approve_for(a)
  local auto_allow = self.config.auto_allow

  if auto_allow == nil then auto_allow = a.policy.auto_allow == true end

  return permissions.new({ ask = self.config.ask, auto_allow = auto_allow })
end

function SessionHub:_session_opts(a, extra)
  return vim.tbl_extend('force', {
    approve = self:_approve_for(a),
    elicit = self.config.elicit,
    admit = self._admit,
  }, extra)
end

function SessionHub:_resolve_agent(name)
  local found = agent.get(name or self.config.agent)

  if not found then
    local wanted = name or self.config.agent or agent.default_name or agent.DEFAULT

    return nil, 'unknown agent: ' .. tostring(wanted)
  end

  return found
end

function SessionHub:_new_key()
  self._next_key = self._next_key + 1

  return 'h' .. self._next_key
end

function SessionHub:_open(key, opts)
  local a, err = self:_resolve_agent(opts.agent)

  if err then return nil, err end

  local parent = opts.parent and self.store.get(opts.parent)
  local depth = parent and parent.depth + 1 or 0

  if depth > self.config.max_depth then
    return nil, string.format('sessions may only nest %d deep', self.config.max_depth)
  end

  local dir = opts.dir or (parent and parent.dir) or self:dir()

  if opts.hidden then return self:_open_hidden(key, a, dir, opts) end

  local session, start_err = self:workspace(dir):new_session(
    a,
    self:_session_opts(a, { key = key, parent = parent and parent.key, depth = depth })
  )

  if start_err then return nil, start_err end

  return self.store.add(session)
end

function SessionHub:_open_hidden(key, a, dir, opts)
  local reader = a:derive({ system = opts.system, model = opts.model or a.model, mcp = {}, editor = false })
  local session, err = self:workspace(dir):new_session(reader, {
    key = key,
    title = opts.title,
    hidden = true,
    approve = permissions.new(),
  })

  if err then return nil, err end

  self._hidden[key] = session

  return session
end

function SessionHub:discard(session)
  return async.run(function()
    self._hidden[session.key] = nil

    local _, err = self:workspace(session.dir):delete(session.agent, session.id)

    if err then self:workspace(session.dir):hide(session.id) end

    return true
  end)
end

function SessionHub:start(opts)
  opts = opts or {}

  local key = self:_new_key()

  self._starting[key] = true

  local task = async.run(function()
    local session, err = self:_open(key, opts)

    self._starting[key] = err and tostring(err) or nil

    return session, err
  end)

  task.key = key

  return task
end

function SessionHub:starting(key)
  return self._starting[key]
end

function SessionHub:load(opts)
  return async.run(function()
    local workspace = self:workspace(opts.dir)
    local live = workspace:find(opts.id)

    if live and live.state ~= Session.STATE.closed then return live end

    local a, err = self:_resolve_agent(opts.agent)

    if err then return nil, err end

    local shown
    local session, load_err = workspace:load_session(
      a,
      opts.id,
      self:_session_opts(a, {
        key = self:_new_key(),
        title = opts.title,
        on_session = opts.on_session and function(session)
          shown = self.store.add(session)
          opts.on_session(session)
        end,
      })
    )

    if load_err then
      if shown then
        self.store.remove(shown.key)
        shown:close()
      end

      return nil, load_err
    end

    return shown or self.store.add(session)
  end)
end

function SessionHub:fork(session, message_id)
  return async.run(function()
    local forked, err = self:workspace(session.dir):fork(
      session,
      message_id,
      self:_session_opts(session.agent, { key = self:_new_key(), title = (session.title or 'untitled') .. ' (fork)' })
    )

    if err then return nil, err end

    return self.store.add(forked)
  end)
end

function SessionHub:list(dir, agent_name)
  return async.run(function()
    local a, err = self:_resolve_agent(agent_name)

    if err then return nil, err end

    return self:workspace(dir):list(a)
  end)
end

function SessionHub:delete(opts)
  return async.run(function()
    local workspace = self:workspace(opts.dir)
    local live = workspace:find(opts.id)
    local a, err = self:_resolve_agent(opts.agent)

    if err then return nil, err end

    local _, delete_err = workspace:delete(a, opts.id)

    if live then self.store.remove(live.key) end

    if delete_err then return nil, delete_err end

    return true
  end)
end

function SessionHub:prompt(session, text, context)
  if not self:admit(session) then
    return nil, string.format('%d turns are already running (max_running)', self.config.max_running)
  end

  return session:prompt(text, context)
end

function SessionHub:send(session, text, context, opts)
  return session:submit(text, context, opts)
end

function SessionHub:reload(session)
  return async.run(function()
    return self:workspace(session.dir):reload(session)
  end)
end

function SessionHub:session(key)
  return self.store.get(key)
end

function SessionHub:sessions(dir)
  return self.store.list(dir)
end

function SessionHub:close(key)
  local session = self.store.get(key)

  if not session then return end

  session:close()
  self.store.remove(key)

  if self.workspaces[session.dir] then self.workspaces[session.dir]:forget(key) end
end

function SessionHub:shutdown()
  for _, workspace in pairs(self.workspaces) do
    workspace:close()
  end

  self.store.clear()
  self.workspaces, self._starting = {}, {}

  return self
end

return SessionHub

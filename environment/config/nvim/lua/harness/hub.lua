local env = require('core.env')
local fs = require('core.fs')
local agent = require('harness.agent')
local async = require('harness.async')
local permissions = require('harness.permissions')
local Workspace = require('harness.workspace')
local session_store = require('harness.session_store')

local hub = {}

hub.config = {
  agent = nil,
  auto_allow = nil,
  max_running = 4,
  max_depth = 2,
  ask = nil,
  spawn = nil,
}

local workspaces = {}
local starting = {}
local next_key = 0

local function lua_root()
  local source = debug.getinfo(1, 'S').source:sub(2)

  return vim.fs.normalize(vim.fs.dirname(source) .. '/..')
end

function hub.dir()
  return fs.cwd()
end

function hub.editor_server(key)
  local addr = env.server_address()

  return {
    name = permissions.MCP_NAME,
    command = env.progpath(),
    args = { '--headless', '-u', 'NONE', '-l', lua_root() .. '/nvim_mcp/run.lua', addr },
    env = { { name = 'HARNESS_SESSION', value = key or '' } },
  }
end

function hub.workspace(dir)
  dir = dir or hub.dir()

  if not workspaces[dir] then
    workspaces[dir] = Workspace(dir, {
      spawn = function(a, d)
        return hub.config.spawn and hub.config.spawn(a, d) or a:spawn(d)
      end,
      servers = function(a, key)
        return vim.list_extend({ hub.editor_server(key) }, a:mcp_servers())
      end,
    })
  end

  return workspaces[dir]
end

local function approve_for(a)
  local auto_allow = hub.config.auto_allow

  if auto_allow == nil then auto_allow = a.policy.auto_allow == true end

  return permissions.new({ ask = hub.config.ask, auto_allow = auto_allow })
end

local function register(session)
  return session_store.add(session)
end

local function resolve_agent(name)
  local found = agent.get(name or hub.config.agent)

  if not found then
    local wanted = name or hub.config.agent or agent.default_name or agent.DEFAULT

    error('unknown agent: ' .. tostring(wanted), 0)
  end

  return found
end

local function new_key()
  next_key = next_key + 1

  return 'h' .. next_key
end

function hub.start(opts)
  opts = opts or {}

  local key = new_key()

  starting[key] = true

  local task = async.run(function()
    local ok, session = pcall(function()
      local a = resolve_agent(opts.agent)
      local parent = opts.parent and session_store.get(opts.parent)
      local depth = parent and parent.depth + 1 or 0

      if depth > hub.config.max_depth then
        error(string.format('sessions may only nest %d deep', hub.config.max_depth), 0)
      end

      local dir = opts.dir or (parent and parent.dir) or hub.dir()

      return register(hub.workspace(dir):new_session(a, {
        key = key,
        approve = approve_for(a),
        parent = parent and parent.key,
        depth = depth,
      }))
    end)

    if not ok then
      starting[key] = tostring(session)
      error(session, 0)
    end

    starting[key] = nil

    return session
  end)

  task.key = key

  return task
end

function hub.starting(key)
  return starting[key]
end

function hub.load(opts)
  return async.run(function()
    local workspace = hub.workspace(opts.dir)
    local live = workspace:find(opts.id)

    if live and live.state ~= 'closed' then return live end

    local a = resolve_agent(opts.agent)
    local shown
    local ok, session = pcall(workspace.load_session, workspace, a, opts.id, {
      key = new_key(),
      approve = approve_for(a),
      title = opts.title,
      on_session = opts.on_session and function(session)
        shown = register(session)
        opts.on_session(session)
      end,
    })

    if not ok then
      if shown then
        session_store.remove(shown.key)
        shown:close()
      end

      error(session, 0)
    end

    return shown or register(session)
  end)
end

function hub.fork(session, message_id)
  return async.run(function()
    local workspace = hub.workspace(session.dir)
    local forked = workspace:fork(session, message_id, {
      key = new_key(),
      approve = approve_for(session.agent),
      title = (session.title or 'untitled') .. ' (fork)',
    })

    return register(forked)
  end)
end

function hub.list(dir, agent_name)
  return async.run(function()
    return hub.workspace(dir):list(resolve_agent(agent_name))
  end)
end

function hub.delete(opts)
  return async.run(function()
    local workspace = hub.workspace(opts.dir)
    local live = workspace:find(opts.id)

    workspace:delete(resolve_agent(opts.agent), opts.id)

    if live then session_store.remove(live.key) end
  end)
end

function hub.running()
  local count = 0

  session_store.each(function(session)
    if session:running() then count = count + 1 end
  end)

  return count
end

function hub.prompt(session, text, context)
  if not session:running() and hub.running() >= hub.config.max_running then
    error(string.format('%d turns are already running (max_running)', hub.config.max_running), 0)
  end

  return session:prompt(text, context)
end

function hub.reload(session)
  return async.run(function()
    return hub.workspace(session.dir):reload(session)
  end)
end

function hub.send(session, text, context, opts)
  if session.reloading then
    session:enqueue(text, context)
    return 'queued'
  end

  if session:running() then
    if opts and opts.steer then
      local task = session:steer(text, context)
      return task and 'steered' or 'queued', task
    end

    session:enqueue(text, context)
    return 'queued'
  end

  return 'started', hub.prompt(session, text, context)
end

function hub.session(key)
  return session_store.get(key)
end

function hub.sessions(dir)
  return session_store.list(dir)
end

function hub.close(key)
  local session = session_store.get(key)

  if not session then return end

  session:close()
  session_store.remove(key)

  if workspaces[session.dir] then workspaces[session.dir]:forget(key) end
end

function hub.shutdown()
  for _, workspace in pairs(workspaces) do
    workspace:close()
  end

  session_store.clear()
  workspaces, starting = {}, {}
end

return hub

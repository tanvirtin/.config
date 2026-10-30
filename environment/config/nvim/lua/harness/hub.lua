local lazy = require('core.lazy')

local fs = lazy('core.fs')
local env = lazy('core.env')
local Timer = lazy('core.Timer')
local agent = lazy('harness.agent')
local async = lazy('harness.async')
local Workspace = lazy('harness.Workspace')
local permissions = lazy('harness.permissions')
local session_store = require('harness.session_store')

local hub = {}

hub.config = {
  agent = nil,
  auto_allow = nil,
  max_running = 4,
  max_depth = 2,
  ask = nil,
  elicit = nil,
  spawn = nil,
}

local workspaces = {}
local starting = {}
local next_key = 0

local function lua_root()
  local source = debug.getinfo(1, 'S').source:sub(2)

  return fs.normalize(fs.dirname(source) .. '/..')
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
        return hub.config.spawn and hub.config.spawn(a, d) or nil
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

function hub.admit(session)
  return session:running() or hub.running() < hub.config.max_running
end

local function session_opts(a, extra)
  return vim.tbl_extend('force', { approve = approve_for(a), elicit = hub.config.elicit, admit = hub.admit }, extra)
end

local function register(session)
  return session_store.add(session)
end

local function resolve_agent(name)
  local found = agent.get(name or hub.config.agent)

  if not found then
    local wanted = name or hub.config.agent or agent.default_name or agent.DEFAULT

    return nil, 'unknown agent: ' .. tostring(wanted)
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

  local function start()
    local a, err = resolve_agent(opts.agent)

    if err then return nil, err end

    local parent = opts.parent and session_store.get(opts.parent)
    local depth = parent and parent.depth + 1 or 0

    if depth > hub.config.max_depth then
      return nil, string.format('sessions may only nest %d deep', hub.config.max_depth)
    end

    local dir = opts.dir or (parent and parent.dir) or hub.dir()
    local session, start_err =
      hub.workspace(dir):new_session(a, session_opts(a, { key = key, parent = parent and parent.key, depth = depth }))

    if start_err then return nil, start_err end

    return register(session)
  end

  local task = async.run(function()
    local session, err = start()

    starting[key] = err and tostring(err) or nil

    return session, err
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

    local a, err = resolve_agent(opts.agent)

    if err then return nil, err end

    local shown
    local session, load_err = workspace:load_session(
      a,
      opts.id,
      session_opts(a, {
        key = new_key(),
        title = opts.title,
        on_session = opts.on_session and function(session)
          shown = register(session)
          opts.on_session(session)
        end,
      })
    )

    if load_err then
      if shown then
        session_store.remove(shown.key)
        shown:close()
      end

      return nil, load_err
    end

    return shown or register(session)
  end)
end

function hub.fork(session, message_id)
  return async.run(function()
    local workspace = hub.workspace(session.dir)
    local forked, err = workspace:fork(
      session,
      message_id,
      session_opts(session.agent, { key = new_key(), title = (session.title or 'untitled') .. ' (fork)' })
    )

    if err then return nil, err end

    return register(forked)
  end)
end

function hub.list(dir, agent_name)
  return async.run(function()
    local a, err = resolve_agent(agent_name)

    if err then return nil, err end

    return hub.workspace(dir):list(a)
  end)
end

function hub.delete(opts)
  return async.run(function()
    local workspace = hub.workspace(opts.dir)
    local live = workspace:find(opts.id)

    local a, err = resolve_agent(opts.agent)

    if err then return nil, err end

    local _, delete_err = workspace:delete(a, opts.id)

    if live then session_store.remove(live.key) end

    if delete_err then return nil, delete_err end

    return true
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
  if not hub.admit(session) then
    return nil, string.format('%d turns are already running (max_running)', hub.config.max_running)
  end

  return session:prompt(text, context)
end

function hub.admit_waiting()
  local waiting = {}

  session_store.each(function(session)
    if session:idle() and session.prompts:size() > 0 then waiting[#waiting + 1] = session end
  end)

  table.sort(waiting, function(a, b)
    return a.prompts:since() < b.prompts:since()
  end)

  for _, session in ipairs(waiting) do
    if hub.running() >= hub.config.max_running then return end

    session.prompts:drain()
  end
end

local function on_session_event(_, event)
  if event.kind == 'stop' then Timer.schedule(hub.admit_waiting) end
end

session_store.on(session_store.EVENT.event, on_session_event)
session_store.on(session_store.EVENT.close, function()
  Timer.schedule(hub.admit_waiting)
end)

function hub.reload(session)
  return async.run(function()
    return hub.workspace(session.dir):reload(session)
  end)
end

hub.SENT = { started = 'started', queued = 'queued', steered = 'steered' }

function hub.send(session, text, context, opts)
  if session:loading() or (session:running() and not (opts and opts.steer)) then
    local _, err = session:enqueue(text, context)

    if err then return nil, err end

    return { how = hub.SENT.queued }
  end

  if session:running() then
    local task, err = session:steer(text, context)

    if err then return nil, err end

    return { how = task and hub.SENT.steered or hub.SENT.queued, task = task }
  end

  if not hub.admit(session) then
    local _, err = session:enqueue(text, context)

    if err then return nil, err end

    return { how = hub.SENT.queued }
  end

  local task, err = hub.prompt(session, text, context)

  if err then return nil, err end

  return { how = hub.SENT.started, task = task }
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

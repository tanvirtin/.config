local lazy = require('core.lazy')

local guides = lazy('ui.guides')
local tools = lazy('nvim_mcp.tools')
local schema = lazy('nvim_mcp.schema')
local hub = lazy('harness.session.hub')
local Window = lazy('core.editor.Window')
local display = lazy('harness.ui.display')
local store = lazy('harness.session.store')
local tool_util = lazy('nvim_mcp.tools.util')
local mascot = lazy('harness.transcript.mascot')
local FleetMember = lazy('harness.transcript.model.FleetMember')
local text_renderer = lazy('harness.transcript.model.text_renderer')

local session_tools = {}

session_tools.WAIT = { default_ms = 120000, max_ms = 600000, retry_ms = 500 }

local prompting = {}

local function fail(message)
  error(message, 0)
end

local function caller_of(ctx)
  return ctx.caller and hub.session(ctx.caller)
end

local function scope(ctx)
  local caller = caller_of(ctx)

  return caller and caller.dir or hub.dir()
end

local function model_of(session)
  local choice = session:choice('model')

  return choice and (choice.name or choice.value) or nil
end

local function cost_of(session)
  local usage = session:usage()

  return usage and usage.cost or nil
end

local function describe(session, ctx)
  return {
    session = session.key,
    agent = session.agent.name,
    model = model_of(session),
    title = session.title,
    state = session.state,
    parent = session.parent,
    depth = session.depth,
    cost = cost_of(session),
    you = session.key == ctx.caller or nil,
  }
end

local function target(key, ctx)
  local session = hub.session(key)

  if not session then
    local starting = hub.starting(key)

    if starting == true then fail('session ' .. key .. ' is still starting; read it again shortly') end
    if starting then fail('session ' .. key .. ' failed to start: ' .. starting) end

    fail('no session ' .. key)
  end

  if session.dir ~= scope(ctx) then fail('session ' .. key .. ' belongs to another directory') end
  if key == ctx.caller then fail('a session cannot drive itself') end

  return session
end

local function prompt(session, text)
  if session:running() then fail('a turn is already running in this session') end

  local sent, err = hub.send(session, text)

  if err then fail(err) end

  if sent.task then sent.task:on_complete(function() end) end
end

local function session_list(_, ctx)
  return vim.tbl_map(function(session)
    return describe(session, ctx)
  end, hub.sessions(scope(ctx)))
end

local function session_new(args, ctx)
  local caller = caller_of(ctx)

  if caller and caller.depth + 1 > hub.config.max_depth then
    fail(string.format('sessions may only nest %d deep; do this work yourself', hub.config.max_depth))
  end

  local task = hub.start({ dir = scope(ctx), agent = args.agent, model = args.model, parent = ctx.caller })

  if args.prompt then prompting[task.key] = true end

  task:on_complete(function(err, session)
    prompting[task.key] = nil

    if err or not args.prompt then return end

    pcall(prompt, session, args.prompt)
  end)

  return { session = task.key, state = 'starting' }
end

local function session_prompt(args, ctx)
  local session = target(args.session, ctx)

  if session:running() then fail('session ' .. args.session .. ' is still running a turn') end

  prompt(session, args.text)

  return { session = session.key, state = 'running' }
end

local function session_read(args, ctx)
  local starting = hub.starting(args.session)

  if starting == true then return { session = args.session, state = 'starting' } end

  local session = target(args.session, ctx)
  local since = args.since or 0
  local events = vim.list_slice(session.history, since + 1)
  local lines = text_renderer.render(events, session.title, { edits = session.edits })

  return {
    session = session.key,
    state = session.state,
    title = session.title,
    next = #session.history,
    transcript = table.concat(lines, '\n', 3),
  }
end

local function settled(key, ctx, waiting)
  local starting = hub.starting(key)

  if starting == true or prompting[key] then return nil end

  local session = target(key, ctx)
  local member = FleetMember.of(session)

  if member.state == FleetMember.STATE.waiting then
    waiting[#waiting + 1] = { session = key, ask = member.ask }
    return nil
  end

  if member.state == FleetMember.STATE.working then return nil end

  return {
    session = key,
    state = member.state,
    model = member.model,
    cost = member.cost,
    ask = member.ask,
    result = member.result,
  }
end

local function session_wait(args, ctx)
  local WAIT = session_tools.WAIT
  local timeout = math.min(args.timeout_ms or WAIT.default_ms, WAIT.max_ms)
  local any = args.until_any == true
  local ready, pending, waiting = {}, {}, {}

  if #args.sessions == 0 then fail('pass at least one session key') end

  for _, key in ipairs(args.sessions) do
    local done = settled(key, ctx, waiting)

    if done then
      ready[#ready + 1] = done
    else
      pending[#pending + 1] = key
    end
  end

  local finished = #pending == 0 or (any and #ready > 0)

  if not finished and (ctx.waited or 0) < timeout then return { _retry_ms = WAIT.retry_ms } end

  return {
    sessions = ready,
    running = #pending > 0 and pending or nil,
    waiting_on_user = #waiting > 0 and waiting or nil,
    timed_out = not finished or nil,
  }
end

local function session_cancel(args, ctx)
  target(args.session, ctx):cancel()

  return { session = args.session }
end

local function session_close(args, ctx)
  target(args.session, ctx)
  hub.close(args.session)

  return { session = args.session, state = 'closed' }
end

local KEY = { name = 'session', type = schema.str({ description = 'Session key, such as h3.' }) }

session_tools.TOOLS = {
  {
    name = 'session_list',
    risk = 'read',
    summary = 'Agent sessions running in this directory: key, agent, title, state, parent and nesting depth. "you" marks your own session.',
    params = {},
    fn = session_list,
  },
  {
    name = 'session_new',
    risk = 'exec',
    summary = 'Start another agent session in this directory, as your child, optionally with a first prompt. It runs in the background, in a buffer of its own the user can open from the session selector; returns its key at once. Follow it with session_read.',
    params = {
      { name = 'prompt', type = schema.str(), optional = true },
      {
        name = 'agent',
        type = schema.str({ description = 'Agent name (default: the configured one).' }),
        optional = true,
      },
      {
        name = 'model',
        type = schema.str({
          description = 'Model to run it on, as the agent names it (such as haiku). Pick the cheapest model that can do the work.',
        }),
        optional = true,
      },
    },
    fn = session_new,
  },
  {
    name = 'session_prompt',
    risk = 'exec',
    summary = 'Send a follow-up prompt to an idle session in this directory. Returns at once; follow it with session_read.',
    params = { KEY, { name = 'text', type = schema.str() } },
    fn = session_prompt,
  },
  {
    name = 'session_read',
    risk = 'read',
    summary = 'A session\'s state and its transcript as text. Pass the returned "next" as since to read only what is new.',
    params = { KEY, { name = 'since', type = schema.int(), optional = true } },
    fn = session_read,
  },
  {
    name = 'session_wait',
    risk = 'read',
    summary = 'Wait until sessions finish their turn, instead of reading them in a loop. A session waiting on the user keeps the wait going, since only the user can answer it. Returns each settled session\'s state, result, ask, model and cost; keys still running come back under running. Waits up to timeout_ms (default 120000, at most 600000).',
    params = {
      { name = 'sessions', type = schema.list(schema.str({ description = 'Session keys, such as h3.' })) },
      { name = 'until_any', type = schema.bool(), optional = true },
      { name = 'timeout_ms', type = schema.int(), optional = true },
    },
    fn = session_wait,
  },
  {
    name = 'session_cancel',
    risk = 'write',
    summary = 'Stop the running turn of a session in this directory.',
    params = { KEY },
    fn = session_cancel,
  },
  {
    name = 'session_close',
    risk = 'write',
    summary = 'End a session in this directory. Its transcript stays open for the user.',
    params = { KEY },
    fn = session_close,
  },
}

function session_tools.anchor(key)
  local session = hub.session(key)
  local view = session and display.view_of(session)
  local tab = Window.current_tab()

  for _, window in ipairs(view and view:windows() or {}) do
    if window:get_tab() == tab then return window.win_id end
  end
end

function session_tools.register()
  tools.register('session', session_tools.TOOLS)
  tool_util.set_anchor(session_tools.anchor)
  guides.set_icon(mascot.still)
  if session_tools._unsubscribe then session_tools._unsubscribe() end

  session_tools._unsubscribe = store.on({ 'event', 'close' }, function(session, update)
    if update == nil or update.kind == 'prompt' then guides.clear(session.key) end
  end)
  tools.observe_edits('session', function(caller, diff)
    local session = caller and hub.session(caller)

    if session then session:record_edit(diff) end
  end)
end

return session_tools

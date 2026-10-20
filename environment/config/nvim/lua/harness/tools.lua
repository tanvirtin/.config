local hub = require('harness.hub')
local schema = require('nvim_mcp.schema')
local tools = require('nvim_mcp.tools')
local transcript = require('harness.ui.transcript')

local session_tools = {}

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

local function describe(session, ctx)
  return {
    session = session.key,
    agent = session.agent.name,
    title = session.title,
    state = session.state,
    parent = session.parent,
    depth = session.depth,
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
  hub.prompt(session, text):on_complete(function() end)
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

  local task = hub.start({ dir = scope(ctx), agent = args.agent, parent = ctx.caller })

  task:on_complete(function(err, session)
    if err then return end

    if args.prompt then prompt(session, args.prompt) end
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
  local lines = transcript.render(events, session.title)

  return {
    session = session.key,
    state = session.state,
    title = session.title,
    next = #session.history,
    transcript = table.concat(lines, '\n', 3),
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

function session_tools.register()
  tools.register('session', session_tools.TOOLS)
end

return session_tools

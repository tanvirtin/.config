local Buffer = require('core.Buffer')
local Window = require('core.Window')
local console = require('core.console')
local async = require('harness.async')
local context = require('harness.context')
local display = require('harness.ui.display')
local edits = require('harness.ui.edits')
local hub = require('harness.hub')
local transcript = require('harness.ui.transcript')
local tools = require('nvim_mcp.tools')

local commands = {}

local function warn(message)
  console.notify('Harness: ' .. message, 'warn')
end

function commands.open(session, opts)
  return transcript.open(session, opts)
end

local function current_view()
  local view = transcript.view() or transcript.last()

  if not view or view.session.state == 'closed' or view.session.dir ~= hub.dir() then return nil end

  return view
end

local function source()
  local view = transcript.view()

  if view and Buffer.exists(view.source_buf) then return { win = view.source_win, buf = view.source_buf } end

  local window = Window.get_current()

  return { win = window.win_id, buf = window:get_buffer().bufnr }
end

function commands.run(prompt, opts, range)
  opts = opts or {}

  local view = current_view()
  local from = source()

  local where = context.capture_buffer(from.buf, range)

  local task = async.run(function()
    local session = view and view.session or async.await(hub.start({ agent = opts.agent }))

    tools.set_focus(from.win, from.buf)
    commands.open(session, { source_win = from.win, source_buf = from.buf })

    local _, turn = hub.send(session, prompt, where)

    return turn and async.await(turn) or nil
  end)

  task:on_complete(function(err)
    if err and not (view and display.showing(view.session)) then warn(tostring(err)) end
  end)

  return task
end

function commands.new(agent_name)
  local from = source()
  local task = async.run(function()
    local session = async.await(hub.start({ agent = agent_name }))

    commands.open(session, { source_win = from.win, source_buf = from.buf })

    return session
  end)

  task:on_complete(function(err)
    if err then warn(tostring(err)) end
  end)

  return task
end

function commands.cancel()
  local view = transcript.view()
  local session = view and view.session

  if not (session and session:running()) then
    for _, candidate in ipairs(hub.sessions()) do
      if candidate:running() then session = candidate end
    end
  end

  if session then require('harness.ui.composer').interrupt(session) end
end

function commands.fork()
  return transcript.report(transcript.fork())
end

function commands.changes()
  return transcript.report(edits.show_changes(transcript.view() or display.last()))
end

local function scoped(action, scope)
  scope = scope ~= '' and scope or nil

  if scope and not edits.SCOPE[scope] then return false, 'choose edit, turn or session' end

  local here = transcript.view()

  if here then return edits[action](here, scope) end
  if scope and scope ~= edits.SCOPE.session then return false, scope .. ' needs the cursor in a transcript' end

  return edits[action](display.last(), edits.SCOPE.session)
end

function commands.revert(scope)
  return transcript.report(scoped('revert', scope))
end

function commands.quickfix(scope)
  return transcript.report(scoped('quickfix', scope))
end

function commands.sessions()
  local from = source()

  return require('harness.ui.sessions').open({
    on_open = function(session)
      commands.open(session, { source_win = from.win, source_buf = from.buf })
    end,
    on_new = function()
      commands.new()
    end,
  })
end

function commands.stats_lines()
  local compact = require('compact')
  local lines = { '| session | title | context | tool output | saved |', '| --- | --- | --- | --- | --- |' }

  for _, session in ipairs(hub.sessions()) do
    local usage

    for i = #session.history, 1, -1 do
      if session.history[i].kind == require('harness.events').KIND.usage then
        usage = session.history[i]
        break
      end
    end

    local stats = compact.stats(session.key)

    lines[#lines + 1] = string.format(
      '| %s | %s | %s | %d tokens in %d calls | %d tokens |',
      session.key,
      session.title or '',
      usage and string.format('%d / %d', usage.used or 0, usage.size or 0) or '-',
      stats.tokens,
      stats.calls,
      stats.saved_tokens
    )
  end

  local all = compact.stats()

  lines[#lines + 1] = ''
  lines[#lines + 1] = string.format(
    'All tool output: %d tokens sent, %d saved against plain JSON (%d calls).',
    all.tokens,
    all.saved_tokens,
    all.calls
  )

  return lines
end

require('harness.session_store').on('start', function(session)
  if session.parent then
    require('core.Timer').defer(0, function()
      commands.open(session, { background = true })
    end)
  end
end)

return commands

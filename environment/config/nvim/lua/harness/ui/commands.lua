local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local Buffer = lazy('core.Buffer')
local Window = lazy('core.Window')
local async = lazy('harness.async')
local console = lazy('core.console')
local tools = lazy('nvim_mcp.tools')
local tour = lazy('harness.ui.tour')
local edits = lazy('harness.ui.edits')
local context = lazy('harness.context')
local settings = lazy('harness.settings')
local display = lazy('harness.ui.display')
local composer = lazy('harness.ui.composer')
local transcript = lazy('harness.ui.transcript')

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
    local session, err = view and view.session, nil

    if not session then
      session, err = async.await(hub.start({ agent = opts.agent }))
    end
    if err then return nil, err end

    tools.set_focus(from.win, from.buf)
    commands.open(session, { source_win = from.win, source_buf = from.buf })

    local sent, send_err = hub.send(session, prompt, where)

    if send_err then return nil, send_err end
    if not sent.task then return nil end

    return async.await(sent.task)
  end)

  task:on_complete(function(err)
    if err and not (view and display.showing(view.session)) then warn(tostring(err)) end
  end)

  return task
end

function commands.new(agent_name)
  local from = source()
  local task = async.run(function()
    local session, err = async.await(hub.start({ agent = agent_name }))

    if err then return nil, err end

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
  local view = transcript.view()

  if not view then return transcript.report(false, 'no session here') end

  return transcript.report(view:fork())
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

local function attach_session()
  local view = transcript.last()

  if view and view.session.state ~= 'closed' then return view.session end

  for _, candidate in pairs(display.views()) do
    if candidate.session.state ~= 'closed' then return candidate.session end
  end
end

function commands.attach_visual()
  local window = Window.get_current()
  local range = window:visual_lines()

  if not range then return false end

  local buf = window:get_buffer().bufnr

  if composer.is_open() then return composer.attach_visual(buf, range) end

  local session = attach_session()

  if not session then return transcript.report(false, 'no transcript to attach this to yet; open one first') end

  composer.open(session, { display = display, insert = true })

  return composer.attach(buf, range)
end

local function tour_session()
  local view = transcript.view() or display.last()

  return view and view.session.key or nil
end

function commands.tour(text)
  text = vim.trim(text or '')

  local word, rest = text:match('^(%S+)%s*(.*)$')
  local session = tour_session()

  if word == 'next' then return transcript.report(tour.next(session)) end
  if word == 'prev' or word == 'previous' or word == 'back' then return transcript.report(tour.previous(session)) end
  if word == 'stop' then return transcript.report(tour.stop(session)) end
  if word == 'resume' then return transcript.report(tour.resume(session)) end

  local here = transcript.view()

  if not word or word == 'changes' or edits.SCOPE[word] then
    local scope = edits.SCOPE[word] or (word == 'changes' and edits.SCOPE[rest]) or nil

    if not scope then scope = here and edits.SCOPE.turn or edits.SCOPE.session end

    return transcript.report(tour.changes(here or display.last(), scope))
  end

  return transcript.report(
    false,
    'ask for a tour in your session; :HarnessTour takes next, prev, stop, resume or changes'
  )
end

local function tab_columns()
  local total, count = 0, 0

  for _, window in ipairs(Window.list_tab()) do
    if window:get_config().relative == '' then
      total = total + window:get_width()
      count = count + 1
    end
  end

  return total + math.max(count - 1, 0)
end

function commands.transcript(action)
  action = vim.trim(action or '')

  if not transcript.view() then return transcript.report(false, 'focus a transcript first') end

  local window = Window.get_current()
  local spec = settings.transcript
  local columns = tab_columns()
  local compact = math.max(spec:get('tile_min_width'), math.floor(columns * spec:get('tile_width')))
  local wide = math.max(compact + 1, math.floor(columns * spec:get('tile_expanded')))

  if action == 'right' then
    window:move_right()
    window:set_width(compact)

    return true
  end

  if action == 'expand' then
    window:set_width(window:get_width() >= wide and compact or wide)

    return true
  end

  return transcript.report(false, 'HarnessTranscript takes expand or right')
end

function commands.permissions()
  local view = transcript.view() or display.last()

  if not view then return transcript.report(false, 'no session here') end

  return view:show_permissions()
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
      if session.history[i].kind == require('harness.types.events').KIND.usage then
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

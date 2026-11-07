local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local Timer = lazy('core.Timer')
local surfaces = lazy('surfaces')
local Buffer = lazy('core.Buffer')
local Window = lazy('core.Window')
local keymap = lazy('core.keymap')
local async = lazy('harness.async')
local tools = lazy('nvim_mcp.tools')
local edits = lazy('harness.ui.edits')
local context = lazy('harness.context')
local notice = lazy('harness.ui.notice')
local display = lazy('harness.ui.display')
local composer = lazy('harness.ui.composer')
local transcript = lazy('harness.ui.transcript')
local walkthrough = lazy('harness.ui.walkthrough')
local global_keys = lazy('harness.ui.global_keys')

local commands = {}

local function choice_hints(action)
  return { { '<CR>', action }, { '<C-n>/<C-p>', 'move' }, { '<Esc>', 'close' } }
end

local function warn(message)
  notice.warn(message)
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
    transcript.open(session, { source_win = from.win, source_buf = from.buf })

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

    transcript.open(session, { source_win = from.win, source_buf = from.buf })

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

local function referenceable(buf)
  local name = Buffer(buf):get_name()

  return name ~= '' and not name:match('^%w+://')
end

local function attach_to(session, buf, range)
  if not composer.is_open(session) then composer.open(session, { display = display, insert = true }) end

  return composer.attach(buf, range, session)
end

local function choose_session(shown, buf, range)
  local items = {}

  for _, view in ipairs(shown) do
    if view.session.state ~= 'closed' then
      items[#items + 1] = {
        label = view.session.key .. ' ' .. (view.session.title or 'untitled'),
        description = view.session:running() and 'running' or 'idle',
        view = view,
      }
    end
  end

  if #items == 0 then
    return transcript.report(false, 'no session to attach this to; start one with ' .. global_keys.sessions())
  end

  keymap.feed('<Esc>', 'nx')

  surfaces.pick({
    title = 'Attach the selection to',
    items = items,
    width = '50vw',
    max_height = 10,
    hints = choice_hints('attach'),
    on_select = function(item)
      Timer.schedule(function()
        display.set_current(item.view)
        attach_to(item.view.session, buf, range)
      end)
    end,
  })

  return true
end

local function attach_range(buf, range)
  if not referenceable(buf) then return transcript.report(false, 'select lines in a file to reference them') end

  local view, shown = display.target()

  if shown then return choose_session(shown, buf, range) end

  if not view or view.session.state == 'closed' then
    return transcript.report(false, 'no session to attach this to; start one with ' .. global_keys.sessions())
  end

  local session = view.session

  if not composer.is_open(session) then composer.open(session, { display = display, insert = true }) end

  return composer.attach(buf, range, session)
end

function commands.attach_visual()
  local window = Window.get_current()
  local range = window:visual_lines()

  if not range then return false end

  return attach_range(window:get_buffer().bufnr, range)
end

function commands.attach_line()
  local window = Window.get_current()
  local line = window:get_cursor()[1]

  return attach_range(window:get_buffer().bufnr, { line, line })
end

local function walkthrough_session()
  local view = transcript.view() or display.last()

  return view and view.session.key or nil
end

function commands.walkthrough(text)
  text = vim.trim(text or '')

  local word, rest = text:match('^(%S+)%s*(.*)$')
  local session = walkthrough_session()

  if word == 'next' then return transcript.report(walkthrough.next(session)) end
  if word == 'prev' or word == 'previous' or word == 'back' then
    return transcript.report(walkthrough.previous(session))
  end
  if word == 'stop' then return transcript.report(walkthrough.stop(session)) end
  if word == 'resume' then return transcript.report(walkthrough.resume(session)) end
  if word == 'overview' then return transcript.report(walkthrough.overview(session)) end

  local here = transcript.view()

  if not word or word == 'changes' or edits.SCOPE[word] then
    local scope = edits.SCOPE[word] or (word == 'changes' and edits.SCOPE[rest]) or nil

    if not scope then scope = here and edits.SCOPE.turn or edits.SCOPE.session end

    return transcript.report(walkthrough.changes(here or display.last(), scope))
  end

  return transcript.report(
    false,
    'ask for a walkthrough in your session; :HarnessWalkthrough takes next, prev, overview, stop, resume or changes'
  )
end

function commands.permissions()
  local view = transcript.view() or display.last()

  if not view then return transcript.report(false, 'no session here') end

  return view:show_permissions()
end

function commands.choose_new()
  local agents = require('harness.agent')
  local default = agents.get().name
  local names = agents.names()

  if #names <= 1 then return commands.new(default) end

  table.sort(names, function(a, b)
    if a == default or b == default then return a == default end

    return a < b
  end)

  surfaces.pick({
    title = 'New session with',
    hints = choice_hints('start'),
    items = vim.tbl_map(function(name)
      return { label = name, description = agents.get(name).description, agent = name }
    end, names),
    width = '50vw',
    max_height = 10,
    on_select = function(item)
      Timer.schedule(function()
        commands.new(item.agent)
      end)
    end,
  })

  return true
end

function commands.sessions()
  local from = source()

  return require('harness.ui.sessions').open({
    on_open = function(session)
      transcript.open(session, { source_win = from.win, source_buf = from.buf })
    end,
    on_new = function(agent_name)
      commands.new(agent_name)
    end,
  })
end

require('harness.session_store').on('start', function(session)
  if session.parent then
    require('core.Timer').defer(0, function()
      transcript.open(session, { background = true })
    end)
  end
end)

return commands

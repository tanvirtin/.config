local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local console = lazy('core.console')
local edits = lazy('harness.ui.edits')
local display = lazy('harness.ui.display')
local TourView = lazy('harness.ui.TourView')
local tour_type = lazy('harness.types.tour')
local tour_store = lazy('harness.tour_store')

local tour = {}

local current, dispose

tour.PROMPT = table.concat({
  'Give me a guided tour of the code to answer this: %s',
  '',
  'Read the code first. Then call the tour_start tool with 3 to 15 steps in reading order: each step is a file, a line range and a short markdown note on what the code does and why it matters here.',
  'Keep your reply to a sentence or two; the tour is the answer.',
}, '\n')

local function warn(message)
  console.notify('Harness: ' .. message, 'warn')
end

function tour.is_active()
  return current ~= nil and current:is_open()
end

function tour.close()
  local view = current

  current = nil

  if view then view:stop() end
end

function tour.start(data, opts)
  tour.close()

  local session = opts and opts.session and hub.session(opts.session)
  local view = session and display.view_of(session)

  current = TourView(data, {
    source_win = view and view.source_win,
    on_stop = function(stopped)
      if current == stopped then current = nil end
      if tour_store.current() == data then tour_store.stop() end
    end,
  })

  local ok, why = current:start()

  if not ok then
    current = nil
    warn(why or 'the tour could not start')
  end

  return ok
end

local function active(method)
  if not tour.is_active() then return false, 'no tour is running' end

  return current[method](current)
end

function tour.next()
  return active('next')
end

function tour.previous()
  return active('previous')
end

function tour.stop()
  if not tour.is_active() then return false, 'no tour is running' end

  tour.close()

  return true
end

function tour.changes(view, scope)
  if not view then return false, 'no session here' end

  scope = scope or edits.SCOPE.turn

  local items = view.edits:locations(view.session.history, edits.scoped(view, scope))

  if #items == 0 then return false, 'no ' .. scope .. ' edits to tour here' end

  local steps = {}

  for _, item in ipairs(items) do
    local note = string.format(
      '**+%d −%d**%s',
      item.added or 0,
      item.removed or 0,
      item.prompt and (' · ' .. item.prompt) or ''
    )

    steps[#steps + 1] = {
      path = item.path,
      line = item.line,
      end_line = item.line + math.max(item.added or 1, 1) - 1,
      title = fs.basename(item.path),
      note = note,
    }
  end

  local data, err = tour_type.parse({
    title = string.format('Changes: %s', scope),
    summary = string.format(
      '%d change%s the agent made, in the order it made them.',
      #steps,
      #steps == 1 and '' or 's'
    ),
    steps = steps,
    source = 'changes',
  }, view.session.dir)

  if not data then return false, err end

  tour_store.start(data, { session = view.session.key })

  return true
end

function tour.ask(view, question)
  if not view then return false, 'open a session first' end

  local sent, err = hub.send(view.session, string.format(tour.PROMPT, question))

  if err then return false, tostring(err) end

  if sent.task then sent.task:on_complete(function() end) end

  return true
end

function tour.register_events()
  if dispose then dispose() end

  dispose = tour_store.on(function(kind, data, opts)
    if kind == tour_store.EVENT.start then
      tour.start(data, opts)
    elseif current and kind == tour_store.EVENT.stop then
      tour.close()
    end
  end)

  return tour
end

return tour

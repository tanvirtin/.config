local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local console = lazy('core.console')
local edits = lazy('harness.ui.edits')
local display = lazy('harness.ui.display')
local composer = lazy('harness.ui.composer')
local TourView = lazy('harness.ui.TourView')
local tour_type = lazy('harness.types.tour')
local tour_store = lazy('harness.tour_store')
local session_store = lazy('harness.session_store')

local tour = {}

local views, last, dispose, dispose_sessions = {}, {}, nil, nil

local function warn(message)
  console.notify('Harness: ' .. message, 'warn')
end

local function key_of(session)
  return type(session) == 'table' and session.key or session
end

local function running(session)
  local key = key_of(session)
  local view = key and views[key]

  return view ~= nil and view:is_open() and key or nil
end

local function only_running()
  local found

  for key, view in pairs(views) do
    if view:is_open() then
      if found then return nil end

      found = key
    end
  end

  return found
end

local function only_last()
  local found

  for key in pairs(last) do
    if found then return nil end

    found = key
  end

  return found
end

local function target(session)
  return running(session) or only_running()
end

function tour.close(session)
  local key = key_of(session)

  if not key then return end

  local view = views[key]

  views[key] = nil

  if view then view:stop() end
end

function tour.start(data, opts)
  local key = opts and opts.session

  if type(key) ~= 'string' or key == '' then return false, 'a tour belongs to a session' end

  tour.close(key)

  local session = hub.session(key)
  local view = session and display.view_of(session)

  views[key] = TourView(data, {
    source_win = view and view.source_win,
    session = key,
    on_ask = function(shown)
      return tour.ask_step(shown.session)
    end,
    on_stop = function(stopped)
      if views[key] == stopped then views[key] = nil end

      last[key] = { tour = data, step = stopped.last_index or 1 }

      if tour_store.current(key) == data then tour_store.stop(key) end
    end,
  })

  local ok, why = views[key]:start(opts and opts.step)

  if ok then
    last[key] = nil
  else
    views[key] = nil
    warn(why or 'the tour could not start')
  end

  return ok
end

function tour.resume(session)
  local key = target(session) or only_last()

  if not key then return false, 'no tour to resume; ask your session for one' end

  local view = views[key]

  if view and view:is_open() then return view:show(view.index) end

  local saved = last[key]

  if not saved then return false, 'no tour to resume; ask your session for one' end

  return tour.start(saved.tour, { session = key, step = saved.step })
end

local function active(session, method)
  local key = target(session)

  if not key then return false, 'no tour is running' end

  return views[key][method](views[key])
end

function tour.next(session)
  return active(session, 'next')
end

function tour.previous(session)
  return active(session, 'previous')
end

function tour.stop(session)
  local key = target(session)

  if not key then return false, 'no tour is running' end

  tour.close(key)

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

  tour_store.start(view.session.key, data)

  return true
end

function tour.step_draft(view)
  local step, index = view:step()
  local lines = {
    string.format(
      '[Tour "%s", step %d/%d%s]',
      view.tour.title,
      index,
      #view.tour.steps,
      step.title and (': ' .. step.title) or ''
    ),
    string.format('%s:%d-%d', step.path, step.line, step.end_line),
  }

  for _, line in ipairs(vim.split(step.note, '\n', { plain = true })) do
    if line ~= '' then lines[#lines + 1] = '> ' .. line end
  end

  vim.list_extend(lines, {
    '',
    '(Answer in this session. If it helps the tour, change it with tour_update: insert steps after this one, replace the rest, or rewrite this step\'s note.)',
    '',
    'Question: ',
  })

  return table.concat(lines, '\n')
end

function tour.ask_step(session)
  local key = target(session)

  if not key then return false, 'no tour is running' end

  local current = hub.session(key)

  if not current then return false, 'the session that started this tour is gone' end

  local view = views[key]

  composer.restore(current, { tour.step_draft(view) })
  composer.open(current, { display = display, insert = true })

  return true
end

function tour.register_events()
  if dispose then dispose() end
  if dispose_sessions then dispose_sessions() end

  dispose = tour_store.on(function(kind, session, data, opts)
    if kind == tour_store.EVENT.start then
      tour.start(data, vim.tbl_extend('force', opts or {}, { session = session }))
    elseif kind == tour_store.EVENT.stop then
      tour.close(session)
    elseif kind == tour_store.EVENT.update then
      local view = views[session]

      if view then
        local ok, why = view:apply(opts)

        if not ok and why then warn(why) end
      end
    elseif kind == tour_store.EVENT.select then
      local view = views[session]

      if view then view:select(opts.path, opts.first, opts.last) end
    end
  end)

  dispose_sessions = session_store.on('close', function(session)
    tour_store.stop(session.key)
  end)

  return tour
end

return tour

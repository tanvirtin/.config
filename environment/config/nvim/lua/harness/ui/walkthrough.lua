local lazy = require('core.lazy')

local fs = lazy('core.fs')
local hub = lazy('harness.hub')
local edits = lazy('harness.ui.edits')
local notice = lazy('harness.ui.notice')
local display = lazy('harness.ui.display')
local composer = lazy('harness.ui.composer')
local session_store = lazy('harness.session_store')
local WalkthroughView = lazy('harness.ui.WalkthroughView')
local walkthrough_type = lazy('harness.types.walkthrough')
local walkthrough_store = lazy('harness.walkthrough_store')

local walkthrough = {}

local views, last, dispose, dispose_sessions = {}, {}, nil, nil

local function warn(message)
  notice.warn(message)
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

function walkthrough.close(session)
  local key = key_of(session)

  if not key then return end

  local view = views[key]

  views[key] = nil

  if view then view:stop() end
end

function walkthrough.start(data, opts)
  local key = opts and opts.session

  if type(key) ~= 'string' or key == '' then return false, 'a walkthrough belongs to a session' end

  walkthrough.close(key)

  local session = hub.session(key)
  local view = session and display.view_of(session)

  views[key] = WalkthroughView(data, {
    source_win = view and view.source_win,
    session = key,
    on_ask = function(shown)
      return walkthrough.ask_step(shown.session)
    end,
    on_stop = function(stopped)
      if views[key] == stopped then views[key] = nil end

      last[key] = { walkthrough = data, step = stopped.last_index or 1 }

      if walkthrough_store.current(key) == data then walkthrough_store.stop(key) end
    end,
  })

  local step = opts and opts.step
  local ok, why

  if step and step > 0 then
    ok, why = views[key]:start(step)
  else
    ok, why = views[key]:start_overview()
  end

  if ok then
    last[key] = nil
  else
    views[key] = nil
    warn(why or 'the walkthrough could not start')

    if walkthrough_store.current(key) == data then walkthrough_store.stop(key) end
  end

  return ok
end

function walkthrough.resume(session)
  local key = target(session) or only_last()

  if not key then return false, 'no walkthrough to resume; ask your session for one' end

  local view = views[key]

  if view and view:is_open() then
    if view.index > 0 then return view:show(view.index, view.part) end

    return view:overview()
  end

  local saved = last[key]

  if not saved then return false, 'no walkthrough to resume; ask your session for one' end

  walkthrough_store.start(key, saved.walkthrough, { step = saved.step })

  return running(key) ~= nil
end

local function active(session, method)
  local key = target(session)

  if not key then
    if walkthrough.resume(session) then return true end

    return false, 'no walkthrough is running; :HarnessWalkthrough resume brings back the last one'
  end

  return views[key][method](views[key])
end

function walkthrough.next(session)
  return active(session, 'next')
end

function walkthrough.previous(session)
  return active(session, 'previous')
end

function walkthrough.overview(session)
  return active(session, 'overview')
end

function walkthrough.stop(session)
  local key = target(session)

  if not key then return false, 'no walkthrough is running' end

  walkthrough.close(key)

  return true
end

function walkthrough.changes(view, scope)
  if not view then return false, 'no session here' end

  scope = scope or edits.SCOPE.turn

  local items = view.edits:locations(view.session.history, edits.scoped(view, scope))

  if #items == 0 then return false, 'no ' .. scope .. ' edits to walkthrough here' end

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

  local data, err = walkthrough_type.parse({
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

  walkthrough_store.start(view.session.key, data)

  return true
end

function walkthrough.step_draft(view)
  local step, index, part = view:step()
  local ranges = WalkthroughView.ranges(step)
  local lines = {
    string.format(
      '[Walkthrough "%s", step %d/%d%s]',
      view.walkthrough.title,
      index,
      #view.walkthrough.steps,
      step.title and (': ' .. step.title) or ''
    ),
  }

  for at, range in ipairs(ranges) do
    lines[#lines + 1] = string.format(
      '%s:%d-%d%s',
      range.path,
      range.line,
      range.end_line,
      #ranges > 1 and at == part and ' (looking at this one)' or ''
    )
  end

  for _, line in ipairs(vim.split(step.note, '\n', { plain = true })) do
    if line ~= '' then lines[#lines + 1] = '> ' .. line end
  end

  vim.list_extend(lines, {
    '',
    '(Answer in this session. If the answer needs more than a sentence or two, give it its own steps with walkthrough_update: insert after this step, or replace the rest. Use note only to clarify this step.)',
    '',
    'Question: ',
  })

  return table.concat(lines, '\n')
end

function walkthrough.ask_step(session)
  local key = target(session)

  if not key then return false, 'no walkthrough is running' end

  local view = views[key]

  if view.index == 0 then return false, 'open a step to ask about it' end

  local current = hub.session(key)

  if not current then return false, 'the session that started this walkthrough is gone' end

  composer.restore(current, { walkthrough.step_draft(view) })
  composer.open(current, { display = display, insert = true })

  return true
end

function walkthrough.register_events()
  if dispose then dispose() end
  if dispose_sessions then dispose_sessions() end

  dispose = walkthrough_store.on(function(kind, session, data, opts)
    if kind == walkthrough_store.EVENT.start then
      walkthrough.start(data, vim.tbl_extend('force', opts or {}, { session = session }))
    elseif kind == walkthrough_store.EVENT.stop then
      walkthrough.close(session)
    elseif kind == walkthrough_store.EVENT.update then
      local view = views[session]

      if view then
        local ok, why = view:apply(opts)

        if not ok and why then warn(why) end
      end
    elseif kind == walkthrough_store.EVENT.select then
      local view = views[session]

      if view then view:select(opts.path, opts.first, opts.last) end
    end
  end)

  dispose_sessions = session_store.on('close', function(session)
    walkthrough_store.stop(session.key)
  end)

  return walkthrough
end

return walkthrough

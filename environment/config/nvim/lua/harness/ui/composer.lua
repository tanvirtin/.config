local lazy = require('core.lazy')

local Window = lazy('core.Window')
local keymap = lazy('core.keymap')
local console = lazy('core.console')
local session_store = lazy('harness.session_store')
local ComposerView = lazy('harness.ui.ComposerView')
local NOTICE = require('harness.types.events').NOTICE
local ComposerStore = lazy('harness.ui.ComposerStore')

local composer = {}

composer.WINBAR = ComposerView.WINBAR

local store = ComposerStore()
local views = {}
local last

local function active()
  local win_id = Window.get_current().win_id

  for _, view in pairs(views) do
    if view:is_open() and view.element:get_window().win_id == win_id then return view end
  end

  local view = last and views[last]

  return view and view:is_open() and view or nil
end

function composer.winbar(session)
  local drawn = Window.drawn()

  for _, view in pairs(views) do
    if view:is_open() and view.element:get_window().win_id == drawn then return view:winbar() end
  end

  if session then return ComposerView(session, store):winbar() end

  local view = active()

  return view and view:winbar() or ''
end

function composer.view(session)
  if session then
    local view = views[session.key]

    return view and view:is_open() and view or nil
  end

  return active()
end

function composer.target()
  local view = active()

  return view and view.session
end

function composer.is_open(session)
  if session then return composer.view(session) ~= nil end

  for _, view in pairs(views) do
    if view:is_open() then return true end
  end

  return false
end

-- True when this buffer is an open composer's. Nothing else may take over the
-- window it lives in: the buffer is bufhidden=wipe, so replacing it would wipe
-- the composer and leave its split behind.
function composer.owns(bufnr)
  for _, view in pairs(views) do
    if view:is_open() and view.element:get_buffer().bufnr == bufnr then return true end
  end

  return false
end

function composer.attached(session)
  return store:attachments(session.key)
end

function composer.attach(buf, range, session)
  local view = session and composer.view(session) or active()

  if not view then return false end

  return view:attach(buf, range)
end

function composer.attach_visual(buf, range, session)
  local view = session and composer.view(session) or active()

  if not view then return false end

  local window = Window.get_current()

  buf = buf or window:get_buffer().bufnr
  range = range or window:visual_lines()

  if not range or not view:attach(buf, range) then return false end

  keymap.feed('<Esc>')

  return true
end

function composer.close(discard, session)
  local closing = {}

  for key, view in pairs(views) do
    if not session or key == session.key then closing[#closing + 1] = view end
  end

  for _, view in ipairs(closing) do
    views[view.session.key] = nil
    view:close(discard)
  end
end

function composer.send(opts)
  local view = active()

  if view then view:send(opts) end
end

function composer.interrupt(session)
  if not session then return end

  return session:cancel()
end

function composer.model(session, display)
  local view = session and display and display.view_of(session)

  if view then view:pick_model() end
end

function composer.slash()
  local view = active()
  local session = view and view.session
  local complete = session ~= nil and #session.commands > 0 and Window.get_current():get_cursor()[2] == 0

  keymap.feed('/')
  if complete then keymap.feed('<C-x><C-o>') end
end

local function release(view)
  if views[view.session.key] == view then views[view.session.key] = nil end
end

function composer.open(session, opts)
  opts = opts or {}

  local display = opts.display
  local existing = composer.view(session)

  if existing then
    if existing.answering == opts.answer then
      last = session.key
      existing:focus(opts.insert)

      return existing.element
    end

    composer.close(false, session)
  end

  if session.state == 'closed' then return ComposerView.warn('this session has ended') end

  local view = ComposerView(session, store, {
    display = display,
    answering = opts.answer,
    on_interrupt = composer.interrupt,
    on_slash = composer.slash,
    on_model = composer.model,
    on_close = release,
    on_wipe = release,
    on_enter = function()
      last = session.key

      local shown = display and display.view_of(session)

      if shown then display.set_current(shown) end
    end,
  })

  views[session.key] = view
  last = session.key
  view:mount(opts.insert)

  return view.element
end

function composer.complete(findstart, base)
  local view = active()
  local session = view and view.session

  if not session then return findstart == 1 and -3 or {} end

  if findstart == 1 then
    local window = Window.get_current()
    local cursor = window:get_cursor()
    local line = window:get_buffer():get_lines(cursor[1] - 1, cursor[1])[1] or ''
    local word = line:sub(1, cursor[2])

    if word:match('^/%S*$') then return 0 end

    return -3
  end

  local items = {}
  local prefix = base:gsub('^/', '')

  for _, command in ipairs(session.commands) do
    if vim.startswith(command.name, prefix) then
      items[#items + 1] = {
        word = '/' .. command.name .. (command.hint and ' ' or ''),
        abbr = '/' .. command.name .. (command.hint and (' ' .. command.hint) or ''),
        menu = command.description,
      }
    end
  end

  return items
end

function composer.restore(session, texts)
  if #texts == 0 then return end

  local view = composer.view(session) or ComposerView(session, store)

  view:restore(texts)
end

composer.RETURNED_BECAUSE = { failed = 'the turn failed', interrupted = 'interrupted' }

function composer.on_returned(session, texts, reason)
  composer.restore(session, texts)

  console.notify_now(
    string.format(
      'Harness: %s; %d queued message%s moved back to the composer',
      composer.RETURNED_BECAUSE[reason] or composer.RETURNED_BECAUSE.interrupted,
      #texts,
      #texts == 1 and '' or 's'
    )
  )
end

function composer.on_session_event(session, event)
  if event.kind == NOTICE.returned then composer.on_returned(session, event.texts, event.reason) end

  local view = composer.view(session)

  if view then view:refresh() end
end

local dispose

function composer.register_events()
  if dispose then dispose() end

  dispose = session_store.on(session_store.EVENT.event, composer.on_session_event)

  return composer
end

function composer.forget(session)
  store:clear(session.key)
  composer.close(true, session)
end

return composer

local lazy = require('core.lazy')

local Lens = lazy('ui.Lens')
local fs = lazy('core.system.fs')
local console = lazy('core.console')
local client = lazy('harness.client')
local notice = lazy('harness.ui.notice')
local presence = lazy('harness.presence')
local Window = lazy('core.editor.Window')
local geometry = lazy('harness.composer.geometry')
local ComposerView = lazy('harness.composer.View')
local ComposerStore = lazy('harness.composer.Store')
local NOTICE = require('harness.types.events').NOTICE

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

function composer.owns(bufnr)
  for _, view in pairs(views) do
    if view:is_open() and view.element:get_buffer().bufnr == bufnr then return true end
  end

  return false
end

function composer.attach(buf, range, session)
  local view = session and composer.view(session) or active()

  if not view then return false, 'no composer is open' end

  local ok, why = view:attach(buf, range)

  if not ok then return false, why end

  view:focus(true)

  return true
end

function composer.attach_visual(buf, range, session)
  local view = session and composer.view(session) or active()

  if not view then return false end

  local window = Window.get_current()

  buf = buf or window:get_buffer().bufnr
  range = range or window:visual_lines()

  if not range then return false end

  local ok, why = view:attach(buf, range)

  if not ok then return false, why end

  view:focus(true)

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

  return complete and '/<C-x><C-o>' or '/'
end

function composer.reference()
  local window = Window.get_current()
  local cursor = window:get_cursor()
  local line = window:get_buffer():get_lines(cursor[1] - 1, cursor[1])[1] or ''
  local before = line:sub(cursor[2], cursor[2])

  return (cursor[2] == 0 or before:match('%s')) and '@<C-x><C-o>' or '@'
end

function composer.accept(fallback)
  local menu = Window.completion()

  if not menu then return fallback end

  local item = menu.selected or menu.items[1]

  if not item then return '<C-e>' .. fallback end

  local take = menu.selected and '<C-y>' or '<C-n><C-y>'

  return item.word:match('/$') and (take .. '<C-x><C-o>') or take
end

function composer.next_item(fallback)
  return Window.completion() and '<C-n>' or fallback
end

local function reference_start(word)
  local at = word:match('()@"[^"]*$') or word:match('()@[^%s@]*$')

  if at and (at == 1 or word:sub(at - 1, at - 1):match('%s')) then return at - 1 end
end

local function references(base)
  local typed = base:sub(2):gsub('^"', '')
  local items = {}

  for _, path in ipairs(fs.complete(typed)) do
    items[#items + 1] = {
      word = '@' .. (path:find('%s') and ('"' .. path .. (path:match('/$') and '' or '"')) or path),
      abbr = path,
      menu = path:sub(-1) == '/' and 'dir' or 'file',
    }
  end

  return { words = items, refresh = 'always' }
end

local function release(view)
  if views[view.session.key] == view then views[view.session.key] = nil end
end

local chooser

function composer.set_chooser(fn)
  chooser = fn
end

function composer.retarget(view, session)
  if session.key == view.session.key then return view:focus(true) end

  local lines, source, display = view:lines(), view.source, view.display
  local inline = view.place and view.place:request() or nil

  composer.close(true, view.session)

  if ComposerView.has_text(lines) then
    local existing = store:draft(session.key)

    if existing and ComposerView.has_text(existing) then
      lines = vim.list_extend(vim.list_extend(vim.deepcopy(existing), { '' }), lines)
    end

    store:set_draft(session.key, lines)
  end

  return composer.open(session, {
    display = display,
    insert = true,
    source = source,
    inline = inline,
    from = ComposerView.has_text(lines) and view.session.key or nil,
  })
end

composer.delegate = {
  interrupt = composer.interrupt,
  model = composer.model,
  slash = composer.slash,
  reference = composer.reference,
  accept = composer.accept,
  next_item = composer.next_item,
  closed = release,
  wiped = release,
  sent = function(view, request)
    presence.show(view.session, request)
  end,
  retarget = function(view)
    if chooser then chooser(view) end
  end,
  entered = function(view)
    last = view.session.key

    local shown = view.display and view.display.view_of(view.session)

    if shown then view.display.set_current(shown) end
  end,
}

function composer.open(session, opts)
  opts = opts or {}

  local display = opts.display
  local existing = composer.view(session)
  local request = opts.inline and geometry.inline_fits(Window(opts.inline.win)) and opts.inline or nil

  if existing then
    local placed = request == nil or (existing.place ~= nil and existing.place:matches(request))

    if placed and existing.destination:answers() == opts.answer then
      last = session.key
      if opts.source then existing.source = opts.source end
      if opts.from then existing.moved_from = opts.from end
      existing:focus(opts.insert)

      return existing.element
    end

    composer.close(false, session)
  end

  if session.state == 'closed' then return notice.info('this session has ended') end

  presence.clear(session.key)

  local view = ComposerView(session, store, {
    display = display,
    answering = opts.answer,
    delegate = composer.delegate,
    place = request and Lens(Window(request.win), request.line) or nil,
  })

  views[session.key] = view
  last = session.key
  view:mount(opts.insert)

  if opts.source then view.source = opts.source end
  if opts.from then view.moved_from = opts.from end

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

    return reference_start(word) or -3
  end

  if base:sub(1, 1) == '@' then return references(base) end

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

  dispose = client.on(client.events().event, composer.on_session_event)

  return composer
end

function composer.forget(session)
  store:clear(session.key)
  composer.close(true, session)
end

return composer

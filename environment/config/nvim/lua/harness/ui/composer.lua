local lazy = require('core.lazy')

local Window = lazy('core.Window')
local keymap = lazy('core.keymap')
local console = lazy('core.console')
local display = lazy('harness.ui.display_api')
local session_store = lazy('harness.session_store')
local ComposerView = lazy('harness.ui.ComposerView')
local NOTICE = require('harness.types.events').NOTICE
local ComposerStore = lazy('harness.ui.ComposerStore')

local composer = {}

composer.WINBAR = ComposerView.WINBAR

local store = ComposerStore()
local current

function composer.winbar(session)
  if session and not (current and current.session == session) then return ComposerView(session, store):winbar() end

  return current and current:winbar() or ''
end

function composer.target()
  return current and current.session
end

function composer.is_open()
  return current ~= nil and current:is_open()
end

function composer.attached(session)
  return store:attachments(session.key)
end

function composer.attach(buf, range)
  if not composer.is_open() then return false end

  return current:attach(buf, range)
end

function composer.attach_visual()
  if not composer.is_open() then return false end

  local window = Window.get_current()
  local range = window:visual_lines()

  if not range or not current:attach(window:get_buffer().bufnr, range) then return false end

  keymap.feed('<Esc>')

  return true
end

function composer.detach(session)
  if not session then return end

  store:detach(session.key)
  Window.redraw_bars()
end

function composer.close(discard)
  if not current then return end

  local closing = current

  current = nil
  closing:close(discard)
end

function composer.send(opts)
  if not current then return end

  current:send(opts)
end

function composer.interrupt(session)
  if not session then return end

  return session:cancel()
end

function composer.model(session)
  local view = session and display.view_of(session)

  if view then view:pick_model() end
end

function composer.slash()
  local session = current and current.session
  local complete = session ~= nil and #session.commands > 0 and Window.get_current():get_cursor()[2] == 0

  keymap.feed('/')
  if complete then keymap.feed('<C-x><C-o>') end
end

local function release(view)
  if current == view then current = nil end
end

function composer.open(session, opts)
  opts = opts or {}

  if composer.is_open() then
    if current.session == session then
      current:focus(opts.insert)
      return current.element
    end

    composer.close()
  end

  if session.state == 'closed' then return ComposerView.warn('this session has ended') end

  current = ComposerView(session, store, {
    on_interrupt = composer.interrupt,
    on_slash = composer.slash,
    on_model = composer.model,
    on_close = release,
    on_wipe = release,
  }):mount(opts.insert)

  return current.element
end

function composer.complete(findstart, base)
  local session = current and current.session

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

  local view = current and current.session == session and current or ComposerView(session, store)

  view:restore(texts)
end

function composer.on_returned(session, texts)
  composer.restore(session, texts)

  console.notify_now(
    string.format(
      'Harness: interrupted; %d queued message%s moved back to the composer',
      #texts,
      #texts == 1 and '' or 's'
    )
  )
end

function composer.on_session_event(session, event)
  if event.kind == NOTICE.returned then composer.on_returned(session, event.texts) end
end

local dispose

function composer.register_events()
  if dispose then dispose() end

  dispose = session_store.on(session_store.EVENT.event, composer.on_session_event)

  return composer
end

function composer.forget(session)
  store:clear(session.key)

  if current and current.session == session then composer.close(true) end
end

require('harness.ui.composer_api').install(composer)

return composer

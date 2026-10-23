local lazy = require('core.lazy')

local Buffer = require('core.Buffer')
local Element = require('ui.elements.Element')
local Timer = require('core.Timer')
local Window = require('core.Window')
local console = require('core.console')
local context = require('harness.context')
local hub = require('harness.hub')
local keymap = require('core.keymap')
local permission_prompt = require('harness.ui.permission_prompt')
local settings = require('harness.settings')
local tools = require('nvim_mcp.tools')
local theme = require('harness.transcript.theme')

local display = lazy('harness.ui.display')

local composer = {}

local current
local drafts = {}
local attached = {}

local function warn(message)
  console.notify('Harness: ' .. message, 'warn')
end

composer.WINBAR = '%!v:lua.require\'harness.ui.composer\'.winbar()'

local function key(lhs, label)
  return '%#UiAccent#' .. lhs .. ' %#UiMuted#' .. label .. '  '
end

function composer.winbar(session)
  session = session or (current and current.session)

  if not session then return '' end

  local title = (session.title or 'untitled'):gsub('%%', '%%%%')
  local parts = { '%#UiTitle# ' .. theme.PROMPT_ICON .. ' ' .. session.key .. ' ' .. title .. ' %*' }

  local mode = session:mode()

  if mode then
    parts[#parts + 1] = '%#UiAccent#' .. theme.MODE_FORMAT:format(mode.name or mode.id):gsub('%%', '%%%%') .. ' '
  end
  if #session.queue > 0 then
    parts[#parts + 1] = string.format('%%#UiMuted#%s%d queued ', theme.QUEUE_ICON, #session.queue)
  end
  for _, selection in ipairs(attached[session.key] or {}) do
    parts[#parts + 1] = '%#UiPath#+ ' .. selection.label:gsub('%%', '%%%%') .. ' '
  end

  if session.external then parts[#parts + 1] = '%#UiWarn#⇄ also driven elsewhere: sending forks it ' end
  if #permission_prompt.asks_of(session) > 0 then
    parts[#parts + 1] = '%#UiWarn#' .. theme.WAITING_ICON[1] .. 'answer in the transcript '
  end

  parts[#parts + 1] = '%='

  local keys = settings.keymaps:get('composer')

  if session:running() then
    parts[#parts + 1] = key(keys.send, 'queue')
    if session.connection:steering() then parts[#parts + 1] = key(keys.steer, 'steer') end
    parts[#parts + 1] = key(keys.interrupt, 'interrupt')
  else
    parts[#parts + 1] = key(keys.send, 'send')
  end

  if #session.commands > 0 then parts[#parts + 1] = key(keys.slash, 'commands') end
  if session:mode() then parts[#parts + 1] = key(keys.cycle_mode, 'mode') end
  if attached[session.key] then parts[#parts + 1] = key(keys.detach, 'drop selection') end
  parts[#parts + 1] = key(keys.close, 'close')

  return table.concat(parts)
end

local function lines_of()
  return current and current.element:is_valid() and current.element:get_lines() or {}
end

local function has_text(lines)
  return vim.trim(table.concat(lines, '\n')) ~= ''
end

local function focus(win)
  local window = type(win) == 'number' and Window(win)

  if window and window:is_valid() then window:focus() end
end

function composer.attached(session)
  return attached[session.key] or {}
end

function composer.attach(buf, range)
  if not composer.is_open() or buf == current.element:get_buffer().bufnr or not Buffer.exists(buf) then return false end

  local buffer = Buffer(buf)
  local key = current.session.key
  local selection = context.selection(buffer, range)

  selection.range = { range[1], range[2] }
  attached[key] = attached[key] or {}
  attached[key][#attached[key] + 1] = selection
  Window.redraw_bars()

  return true
end

function composer.attach_visual()
  if not composer.is_open() then return false end

  local window = Window.get_current()
  local range = window:visual_lines()

  if not range or not composer.attach(window:get_buffer().bufnr, range) then return false end

  keymap.feed('<Esc>')

  return true
end

function composer.detach(session)
  local list = session and attached[session.key]

  if not list then return end

  list[#list] = nil
  if #list == 0 then attached[session.key] = nil end
  Window.redraw_bars()
end

function composer.target()
  return current and current.session
end

function composer.is_open()
  return current ~= nil and current.element:is_valid()
end

function composer.close(discard)
  if not current then return end

  local closing = current
  current = nil

  if closing.element:is_valid() then
    local lines = closing.element:get_lines()

    drafts[closing.session.key] = has_text(lines) and lines or nil
    closing.element:unmount()
  end

  if discard then
    drafts[closing.session.key] = nil
    attached[closing.session.key] = nil
  end

  focus(closing.origin)
end

local function reveal(session, origin, source)
  return display.reveal(session, origin, source)
end

local function deliver(outgoing, opts)
  local session, source = outgoing.session, outgoing.source
  local text = vim.trim(table.concat(outgoing.lines, '\n'))

  if text == '' then return true end
  if session.state == 'closed' then return false, 'this session has ended; your text is kept' end

  local where = Buffer.exists(source.buf) and context.capture_buffer(source.buf) or nil

  for _, selection in ipairs(attached[session.key] or {}) do
    where = context.attach(where or {}, selection)
  end

  local ok, how, task = pcall(hub.send, session, text, where, opts)

  if not ok then return false, tostring(how) end

  drafts[session.key] = nil
  attached[session.key] = nil

  if source.buf then tools.set_focus(source.win, source.buf) end

  if task then
    task:on_complete(function(err)
      if err and not display.showing(session) then warn(tostring(err)) end
    end)
  end

  return true, how
end

local function outgoing()
  return { session = current.session, lines = lines_of(), source = current.source, origin = current.origin }
end

function composer.send(opts)
  if not current then return end

  local message = outgoing()
  local sent, why = deliver(message, opts)

  if not sent then return warn(why) end

  local shown = reveal(message.session, message.origin, message.source)

  composer.close(true)
  focus(shown)
end

local function send_after_write(message)
  Timer.schedule(function()
    local sent, why = deliver(message)

    if not sent then
      drafts[message.session.key] = message.lines
      return warn(why)
    end

    local shown = reveal(message.session, message.origin, message.source)

    if current and current.session == message.session then composer.close(true) end
    focus(shown)
  end)
end

function composer.open(session, opts)
  opts = opts or {}

  if current and current.element:is_valid() then
    if current.session == session then
      current.element:focus()
      if opts.insert then current.element:start_insert() end
      return current.element
    end

    composer.close()
  end

  if session.state == 'closed' then return warn('this session has ended') end

  local element = Element({
    buf_options = {
      buftype = 'acwrite',
      bufhidden = 'wipe',
      swapfile = false,
      buflisted = false,
      filetype = 'markdown',
    },
    win_options = {
      winbar = composer.WINBAR,
      winfixheight = true,
      wrap = true,
      linebreak = true,
      number = false,
      relativenumber = false,
      signcolumn = 'no',
    },
    win_plot = { split = 'below', win = -1, height = settings.composer:get('height') },
  })

  local origin = Window.get_current().win_id
  local keys = settings.keymaps:get('composer')
  local view = display.view_of(session)

  element:mount()
  element:set_name('harness://composer')
  current = {
    element = element,
    session = session,
    origin = origin,
    source = { win = view and view.source_win, buf = view and view.source_buf },
  }

  local draft = drafts[session.key]

  element:set_lines(draft or { '' })
  element:set_buf_option('modified', false)
  element:focus()
  element:set_cursor({ element:get_line_count(), #(element:get_lines()[element:get_line_count()] or '') })

  element:set_keymap('n', keys.send, function()
    composer.send()
  end, 'Send, or queue while the agent works')

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, keys.steer, function()
      Window.stop_insert()
      composer.send({ steer = true })
    end, 'Steer the running turn (queues if the agent cannot steer)')
  end

  element:set_keymap('n', keys.interrupt, function()
    composer.interrupt(session)
  end, 'Interrupt the running turn')
  element:set_keymap('i', keys.interrupt, function()
    if session:running() then return composer.interrupt(session) end

    Window.stop_insert()
  end, 'Interrupt the running turn, or leave insert mode')

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, keys.cycle_mode, function()
      session:cycle_mode()
    end, 'Next session mode')
  end

  element:set_buf_option('omnifunc', 'v:lua.require\'harness.ui.composer\'.complete')
  element:set_keymap('i', keys.slash, composer.slash, 'Slash commands')
  element:set_keymap('n', keys.close, function()
    composer.close()
  end, 'Close (keeps the draft)')
  element:set_keymap('n', keys.detach, function()
    composer.detach(session)
  end, 'Drop the last attached selection')

  local function keep()
    if current and current.element == element and element:is_valid() then
      local lines = element:get_lines()

      drafts[session.key] = has_text(lines) and lines or nil
      element:set_buf_option('modified', false)
    end
  end

  element:attach_to_changes({
    on_lines = function()
      Timer.schedule(keep)
    end,
  })

  element:on('QuitPre', keep)

  element:on('BufWriteCmd', function()
    element:set_buf_option('modified', false)

    if current and current.element == element then send_after_write(outgoing()) end
  end)

  element:on('BufWipeout', function()
    if current and current.element == element then current = nil end
  end)

  if opts.insert then element:start_insert() end

  return element
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

function composer.slash()
  local session = current and current.session
  local complete = session ~= nil and #session.commands > 0 and Window.get_current():get_cursor()[2] == 0

  keymap.feed('/')
  if complete then keymap.feed('<C-x><C-o>') end
end

function composer.restore(session, texts)
  if #texts == 0 then return end

  local lines = vim.split(table.concat(texts, '\n\n'), '\n', { plain = true })
  local open = current and current.session == session and current.element:is_valid()
  local existing = open and current.element:get_lines() or drafts[session.key]

  if existing and has_text(existing) then
    lines[#lines + 1] = ''
    vim.list_extend(lines, existing)
  end

  drafts[session.key] = lines

  if open then
    current.element:set_lines(lines)
    current.element:set_buf_option('modified', false)
  end
end

function composer.interrupt(session)
  if not session then return end

  return session:cancel()
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

local NOTICE = require('harness.types.events').NOTICE

local function on_session_event(session, event)
  if event.kind == NOTICE.returned then composer.on_returned(session, event.texts) end
end

composer.on_session_event = on_session_event

require('harness.session_store').on('event', on_session_event)

function composer.forget(session)
  drafts[session.key] = nil
  attached[session.key] = nil
  if current and current.session == session then composer.close(true) end
end

return composer

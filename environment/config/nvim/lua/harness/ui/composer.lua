local Element = require('ui.elements.Element')
local context = require('harness.context')
local hub = require('harness.hub')
local tools = require('nvim_mcp.tools')

local composer = {}

composer.HEIGHT = 6

local current
local drafts = {}

local function warn(message)
  vim.schedule(function()
    vim.notify('Harness: ' .. message, vim.log.levels.WARN)
  end)
end

composer.WINBAR = '%!v:lua.require\'harness.ui.composer\'.winbar()'

local function key(lhs, label)
  return '%#UiAccent#' .. lhs .. ' %#UiMuted#' .. label .. '  '
end

function composer.winbar(session)
  session = session or (current and current.session)

  if not session then return '' end

  local title = (session.title or 'untitled'):gsub('%%', '%%%%')
  local parts = { '%#UiTitle# → ' .. session.key .. ' ' .. title .. ' %*' }

  local mode = session:mode()

  if mode then parts[#parts + 1] = '%#UiAccent#󰒓 ' .. (mode.name or mode.id):gsub('%%', '%%%%') .. ' ' end
  if #session.queue > 0 then parts[#parts + 1] = string.format('%%#UiMuted#⏳ %d queued ', #session.queue) end
  if session.external then parts[#parts + 1] = '%#UiWarn#⇄ also driven elsewhere: sending forks it ' end
  if #require('harness.ui.transcript').asks_of(session) > 0 then
    parts[#parts + 1] = '%#UiWarn#󰀦 answer with 1/2/3 in the transcript '
  end

  parts[#parts + 1] = '%='

  if session:running() then
    parts[#parts + 1] = key('<CR>', 'queue')
    if session.connection:steering() then parts[#parts + 1] = key('<C-s>', 'steer') end
    parts[#parts + 1] = key('<C-c>', 'interrupt')
  else
    parts[#parts + 1] = key('<CR>', 'send')
    parts[#parts + 1] = key(':w', 'send')
  end

  if #session.commands > 0 then parts[#parts + 1] = key('/', 'commands') end
  if session:mode() then parts[#parts + 1] = key('<S-Tab>', 'mode') end
  parts[#parts + 1] = key('q', 'close')

  return table.concat(parts)
end

local function lines_of()
  return current and current.element:is_valid() and current.element:get_lines() or {}
end

local function has_text(lines)
  return vim.trim(table.concat(lines, '\n')) ~= ''
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

  if discard then drafts[closing.session.key] = nil end
  if closing.origin and vim.api.nvim_win_is_valid(closing.origin) then vim.api.nvim_set_current_win(closing.origin) end
end

local function reveal(session, origin, source)
  local transcript = require('harness.ui.transcript')
  local buf = transcript.buffer_of(session)

  if buf and #vim.fn.win_findbuf(buf) > 0 then return end

  if origin and vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  else
    vim.cmd('topleft split')
    vim.cmd('setlocal winfixheight< signcolumn< winbar<')
  end

  transcript.open(session, { source_win = source.win, source_buf = source.buf })

  return vim.api.nvim_get_current_win()
end

local function deliver(outgoing, opts)
  local session, source = outgoing.session, outgoing.source
  local text = vim.trim(table.concat(outgoing.lines, '\n'))

  if text == '' then return true end
  if session.state == 'closed' then return false, 'this session has ended; your text is kept' end

  local where = source.buf and vim.api.nvim_buf_is_valid(source.buf) and context.capture_buffer(source.buf) or nil
  local ok, how, task = pcall(hub.send, session, text, where, opts)

  if not ok then return false, tostring(how) end

  drafts[session.key] = nil

  if source.buf then tools.set_focus(source.win, source.buf) end

  if task then task:on_complete(function(err)
    if err then warn(tostring(err)) end
  end) end

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
  if shown and vim.api.nvim_win_is_valid(shown) then vim.api.nvim_set_current_win(shown) end
end

local function send_after_write(message)
  vim.schedule(function()
    local sent, why = deliver(message)

    if not sent then
      drafts[message.session.key] = message.lines
      return warn(why)
    end

    local shown = reveal(message.session, message.origin, message.source)

    if current and current.session == message.session then composer.close(true) end
    if shown and vim.api.nvim_win_is_valid(shown) then vim.api.nvim_set_current_win(shown) end
  end)
end

function composer.open(session, opts)
  opts = opts or {}

  if current and current.element:is_valid() then
    if current.session == session then
      current.element:focus()
      if opts.insert then vim.cmd('startinsert!') end
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
    win_plot = { split = 'below', win = -1, height = composer.HEIGHT },
  })

  local origin = vim.api.nvim_get_current_win()
  local view = require('harness.ui.transcript').view_of(session)

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

  element:set_keymap('n', '<CR>', function()
    composer.send()
  end, 'Send, or queue while the agent works')

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, '<C-s>', function()
      vim.cmd('stopinsert')
      composer.send({ steer = true })
    end, 'Steer the running turn (queues if the agent cannot steer)')
  end

  element:set_keymap('n', '<C-c>', function()
    composer.interrupt(session)
  end, 'Interrupt the running turn')

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, '<S-Tab>', function()
      session:cycle_mode()
    end, 'Next session mode')
  end

  element:set_buf_option('omnifunc', 'v:lua.require\'harness.ui.composer\'.complete')
  element:set_keymap('i', '/', composer.slash, 'Slash commands')
  element:set_keymap('n', 'q', function()
    composer.close()
  end, 'Close (keeps the draft)')

  local function keep()
    if current and current.element == element and element:is_valid() then
      local lines = element:get_lines()

      drafts[session.key] = has_text(lines) and lines or nil
      element:set_buf_option('modified', false)
    end
  end

  element:attach_to_changes({
    on_lines = function()
      vim.schedule(keep)
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

  if opts.insert then vim.cmd('startinsert!') end

  return element
end

function composer.complete(findstart, base)
  local session = current and current.session

  if not session then return findstart == 1 and -3 or {} end

  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local word = line:sub(1, col)

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
  local complete = session ~= nil and #session.commands > 0 and vim.api.nvim_win_get_cursor(0)[2] == 0

  vim.api.nvim_feedkeys('/', 'n', false)
  if complete then vim.api.nvim_feedkeys(vim.keycode('<C-x><C-o>'), 'n', false) end
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

  vim.notify(
    string.format(
      'Harness: interrupted; %d queued message%s moved back to the composer',
      #texts,
      #texts == 1 and '' or 's'
    )
  )
end

local NOTICE = require('harness.events').NOTICE

local function on_session_event(session, event)
  if event.kind == NOTICE.returned then composer.on_returned(session, event.texts) end
end

composer.on_session_event = on_session_event

require('harness.session_store').on('event', on_session_event)

function composer.forget(session)
  drafts[session.key] = nil
  if current and current.session == session then composer.close(true) end
end

return composer

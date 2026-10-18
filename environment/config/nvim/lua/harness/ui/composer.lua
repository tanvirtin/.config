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

local HINTS = { { '<CR>', 'send' }, { ':w', 'send' }, { 'q', 'close' } }

local function footer()
  local chunks = { { ' ', 'UiMuted' } }

  for i, hint in ipairs(HINTS) do
    if i > 1 then chunks[#chunks + 1] = { '  ', 'UiMuted' } end
    chunks[#chunks + 1] = { hint[1], 'UiAccent' }
    chunks[#chunks + 1] = { ' ' .. hint[2], 'UiMuted' }
  end

  chunks[#chunks + 1] = { ' ', 'UiMuted' }

  return chunks
end

local function geometry()
  local width = math.max(20, vim.o.columns - 4)
  local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)

  return {
    relative = 'editor',
    width = width,
    height = composer.HEIGHT,
    row = math.max(0, bottom - composer.HEIGHT - 2),
    col = math.floor((vim.o.columns - width - 2) / 2),
  }
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
  if origin and vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end

  transcript.open(session, { source_win = source.win, source_buf = source.buf })
end

local function deliver(outgoing)
  local session, source = outgoing.session, outgoing.source
  local text = vim.trim(table.concat(outgoing.lines, '\n'))

  if text == '' then return true end
  if session.state == 'closed' then return false, 'this session has ended; your text is kept' end

  local where = source.buf and vim.api.nvim_buf_is_valid(source.buf) and context.capture_buffer(source.buf) or nil
  local ok, task = pcall(hub.prompt, session, text, where)

  if not ok then return false, tostring(task) end

  drafts[session.key] = nil

  if source.buf then tools.set_focus(source.win, source.buf) end

  task:on_complete(function(err)
    if err then warn(tostring(err)) end
  end)

  return true
end

local function outgoing()
  return { session = current.session, lines = lines_of(), source = current.source, origin = current.origin }
end

function composer.send()
  if not current then return end

  local message = outgoing()
  local sent, why = deliver(message)

  if not sent then return warn(why) end

  composer.close(true)
  reveal(message.session, message.origin, message.source)
end

local function send_after_write(message)
  vim.schedule(function()
    local sent, why = deliver(message)

    if not sent then
      drafts[message.session.key] = message.lines
      return warn(why)
    end

    if current and current.session == message.session then composer.close(true) end

    reveal(message.session, message.origin, message.source)
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

  local plot = geometry()

  plot.border = 'rounded'
  plot.style = 'minimal'
  plot.title = { { ' → ' .. session.key .. ' ' .. (session.title or 'untitled') .. ' ', 'UiTitle' } }
  plot.title_pos = 'left'
  plot.footer = footer()
  plot.footer_pos = 'right'

  local element = Element({
    buf_options = {
      buftype = 'acwrite',
      bufhidden = 'wipe',
      swapfile = false,
      buflisted = false,
      filetype = 'markdown',
    },
    win_options = {
      winhl = 'Normal:UiNormal,FloatBorder:UiBorder,FloatTitle:UiTitle,FloatFooter:UiMuted',
      wrap = true,
      linebreak = true,
    },
    win_plot = plot,
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

  element:set_keymap('n', '<CR>', composer.send, 'Send to the session')
  element:set_keymap('n', 'q', function()
    composer.close()
  end, 'Close (keeps the draft)')
  element:set_keymap('n', '<Esc>', function()
    composer.close()
  end, 'Close (keeps the draft)')

  element:on({ 'TextChanged', 'TextChangedI' }, function()
    if current and current.element == element then
      local lines = element:get_lines()

      drafts[session.key] = has_text(lines) and lines or nil
      element:set_buf_option('modified', false)
    end
  end)

  element:on('QuitPre', function()
    if current and current.element == element then
      local lines = element:get_lines()

      drafts[session.key] = has_text(lines) and lines or nil
      element:set_buf_option('modified', false)
    end
  end)

  element:on('BufWriteCmd', function()
    element:set_buf_option('modified', false)

    if current and current.element == element then send_after_write(outgoing()) end
  end)

  element:on('WinLeave', function()
    vim.schedule(function()
      if current and current.element == element and not element:is_focused() then composer.close() end
    end)
  end)

  if opts.insert then vim.cmd('startinsert!') end

  return element
end

function composer.forget(session)
  drafts[session.key] = nil
  if current and current.session == session then composer.close(true) end
end

return composer

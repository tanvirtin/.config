local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local Timer = lazy('core.Timer')
local Buffer = lazy('core.Buffer')
local Object = lazy('core.Object')
local Window = lazy('core.Window')
local console = lazy('core.console')
local tools = lazy('nvim_mcp.tools')
local context = lazy('harness.context')
local settings = lazy('harness.settings')
local display = lazy('harness.ui.display')
local Element = lazy('ui.elements.Element')
local theme = lazy('harness.transcript.theme')
local permission_prompt = lazy('harness.ui.permission_prompt')

local ComposerView = Object:extend()

ComposerView.NAME = 'harness://composer'

ComposerView.WINBAR = '%!v:lua.require\'harness.ui.composer\'.winbar()'

ComposerView.OMNIFUNC = 'v:lua.require\'harness.ui.composer\'.complete'

function ComposerView.has_text(lines)
  return vim.trim(table.concat(lines, '\n')) ~= ''
end

function ComposerView.warn(message)
  console.notify('Harness: ' .. message, 'warn')
end

function ComposerView.focus_window(win)
  local window = type(win) == 'number' and Window(win)

  if window and window:is_valid() then window:focus() end
end

function ComposerView:constructor(session, store, callbacks)
  callbacks = callbacks or {}

  return {
    session = session,
    store = store,
    element = nil,
    origin = nil,
    source = {},
    on_send = callbacks.on_send,
    on_slash = callbacks.on_slash,
    on_interrupt = callbacks.on_interrupt,
    on_close = callbacks.on_close,
    on_wipe = callbacks.on_wipe,
  }
end

function ComposerView:is_open()
  return self.element ~= nil and self.element:is_valid()
end

function ComposerView:lines()
  return self:is_open() and self.element:get_lines() or {}
end

function ComposerView:focus(insert)
  self.element:focus()

  if insert then self.element:start_insert() end

  return self
end

function ComposerView:_key(lhs, label)
  return '%#UiAccent#' .. lhs .. ' %#UiMuted#' .. label .. '  '
end

function ComposerView:winbar()
  local session, store = self.session, self.store
  local title = (session.title or 'untitled'):gsub('%%', '%%%%')
  local parts = { '%#UiTitle# ' .. theme.PROMPT_ICON .. ' ' .. session.key .. ' ' .. title .. ' %*' }
  local mode = session:mode()

  if mode then
    parts[#parts + 1] = '%#UiAccent#' .. theme.MODE_FORMAT:format(mode.name or mode.id):gsub('%%', '%%%%') .. ' '
  end
  if #session.queue > 0 then
    parts[#parts + 1] = string.format('%%#UiMuted#%s%d queued ', theme.QUEUE_ICON, #session.queue)
  end
  for _, selection in ipairs(store:attachments(session.key)) do
    parts[#parts + 1] = '%#UiPath#+ ' .. selection.label:gsub('%%', '%%%%') .. ' '
  end

  if session.external then parts[#parts + 1] = '%#UiWarn#⇄ also driven elsewhere: sending forks it ' end
  if #permission_prompt.asks_of(session) > 0 then
    parts[#parts + 1] = '%#UiWarn#' .. theme.WAITING_ICON[1] .. 'answer in the transcript '
  end

  parts[#parts + 1] = '%='

  local keys = settings.keymaps:get('composer')

  if session:running() then
    parts[#parts + 1] = self:_key(keys.send, 'queue')
    if session:can('steer') then parts[#parts + 1] = self:_key(keys.steer, 'steer') end
    parts[#parts + 1] = self:_key(keys.interrupt, 'interrupt')
  else
    parts[#parts + 1] = self:_key(keys.send, 'send')
  end

  if #session.commands > 0 then parts[#parts + 1] = self:_key(keys.slash, 'commands') end
  if session:mode() then parts[#parts + 1] = self:_key(keys.cycle_mode, 'mode') end
  if store:has_attachments(session.key) then parts[#parts + 1] = self:_key(keys.detach, 'drop selection') end
  parts[#parts + 1] = self:_key(keys.close, 'close')

  return table.concat(parts)
end

function ComposerView:attach(buf, range)
  if buf == self.element:get_buffer().bufnr or not Buffer.exists(buf) then return false end

  self.store:attach(self.session.key, context.selection(Buffer(buf), range))
  Window.redraw_bars()

  return true
end

function ComposerView:_keep()
  if not self:is_open() then return self end

  local lines = self.element:get_lines()

  self.store:set_draft(self.session.key, ComposerView.has_text(lines) and lines or nil)
  self.element:set_buf_option('modified', false)

  return self
end

function ComposerView:close(discard)
  local key = self.session.key

  if self:is_open() then
    local lines = self.element:get_lines()

    self.store:set_draft(key, ComposerView.has_text(lines) and lines or nil)
    self.element:unmount()
  end

  if discard then self.store:clear(key) end

  if self.on_close then self.on_close(self) end

  ComposerView.focus_window(self.origin)

  return self
end

function ComposerView:_outgoing()
  return { session = self.session, lines = self:lines(), source = self.source, origin = self.origin }
end

function ComposerView:_deliver(message, opts)
  local session, source, store = message.session, message.source, self.store
  local text = vim.trim(table.concat(message.lines, '\n'))

  if text == '' then return true end
  if session.state == 'closed' then return false, 'this session has ended; your text is kept' end

  local where = Buffer.exists(source.buf) and context.capture_buffer(source.buf) or nil

  for _, selection in ipairs(store:attachments(session.key)) do
    where = context.attach(where, selection)
  end

  local sent, err = hub.send(session, text, where, opts)

  if err then return false, tostring(err) end

  store:clear(session.key)

  if source.buf then tools.set_focus(source.win, source.buf) end

  if sent.task then
    sent.task:on_complete(function(turn_err)
      if turn_err and not display.showing(session) then ComposerView.warn(tostring(turn_err)) end
    end)
  end

  return true, sent.how
end

function ComposerView:send(opts)
  local message = self:_outgoing()
  local sent, why = self:_deliver(message, opts)

  if not sent then return ComposerView.warn(why) end

  local shown = display.reveal(message.session, message.origin, message.source)

  self:close(true)
  ComposerView.focus_window(shown)

  return self
end

function ComposerView:_send_after_write()
  local message = self:_outgoing()

  Timer.schedule(function()
    local sent, why = self:_deliver(message)

    if not sent then
      self.store:set_draft(message.session.key, message.lines)
      return ComposerView.warn(why)
    end

    local shown = display.reveal(message.session, message.origin, message.source)

    if self:is_open() then self:close(true) end
    ComposerView.focus_window(shown)
  end)

  return self
end

function ComposerView:restore(texts)
  local lines = vim.split(table.concat(texts, '\n\n'), '\n', { plain = true })
  local existing = self:is_open() and self.element:get_lines() or self.store:draft(self.session.key)

  if existing and ComposerView.has_text(existing) then
    lines[#lines + 1] = ''
    vim.list_extend(lines, existing)
  end

  self.store:set_draft(self.session.key, lines)

  if self:is_open() then
    self.element:set_lines(lines)
    self.element:set_buf_option('modified', false)
  end

  return self
end

function ComposerView:_bind(keys)
  local element, session = self.element, self.session

  element:set_keymap('n', keys.send, function()
    self:send()
  end, 'Send, or queue while the agent works')

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, keys.steer, function()
      Window.stop_insert()
      self:send({ steer = true })
    end, 'Steer the running turn (queues if the agent cannot steer)')
  end

  element:set_keymap('n', keys.interrupt, function()
    self.on_interrupt(session)
  end, 'Interrupt the running turn')
  element:set_keymap('i', keys.interrupt, function()
    if session:running() then return self.on_interrupt(session) end

    Window.stop_insert()
  end, 'Interrupt the running turn, or leave insert mode')

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, keys.cycle_mode, function()
      session:cycle_mode()
    end, 'Next session mode')
  end

  element:set_buf_var('completion', false)
  element:set_buf_option('omnifunc', ComposerView.OMNIFUNC)
  element:set_keymap('i', keys.slash, self.on_slash, 'Slash commands')
  element:set_keymap('n', keys.close, function()
    self:close()
  end, 'Close (keeps the draft)')
  element:set_keymap('n', keys.detach, function()
    self.store:detach(session.key)
    Window.redraw_bars()
  end, 'Drop the last attached selection')

  return self
end

function ComposerView:_listen()
  local element = self.element

  element:attach_to_changes({
    on_lines = function()
      Timer.schedule(function()
        self:_keep()
      end)
    end,
  })

  element:on('QuitPre', function()
    self:_keep()
  end)

  element:on('BufWriteCmd', function()
    element:set_buf_option('modified', false)

    if self:is_open() then self:_send_after_write() end
  end)

  element:on('BufWipeout', function()
    if self.on_wipe then self.on_wipe(self) end
  end)

  return self
end

function ComposerView:mount(insert)
  local session = self.session
  local view = display.view_of(session)
  local element = Element({
    buf_options = {
      buftype = 'acwrite',
      bufhidden = 'wipe',
      swapfile = false,
      buflisted = false,
      filetype = 'markdown',
    },
    win_options = {
      winbar = ComposerView.WINBAR,
      winfixheight = true,
      wrap = true,
      linebreak = true,
      number = false,
      relativenumber = false,
      signcolumn = 'no',
    },
    win_plot = { split = 'below', win = -1, height = settings.composer:get('height') },
  })

  self.origin = Window.get_current().win_id
  self.source = { win = view and view.source_win, buf = view and view.source_buf }
  self.element = element

  element:mount()
  element:set_name(ComposerView.NAME)
  element:set_lines(self.store:draft(session.key) or { '' })
  element:set_buf_option('modified', false)
  element:focus()
  element:set_cursor({ element:get_line_count(), #(element:get_lines()[element:get_line_count()] or '') })

  self:_bind(settings.keymaps:get('composer')):_listen()

  if insert then element:start_insert() end

  return self
end

return ComposerView

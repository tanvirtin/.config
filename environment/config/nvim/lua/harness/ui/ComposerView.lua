local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local event = lazy('core.event')
local motion = lazy('ui.motion')
local surfaces = lazy('surfaces')
local Buffer = lazy('core.Buffer')
local Object = lazy('core.Object')
local Window = lazy('core.Window')
local keymap = lazy('core.keymap')
local asks = lazy('harness.ui.asks')
local context = lazy('harness.context')
local notice = lazy('harness.ui.notice')
local settings = lazy('harness.settings')
local Element = lazy('ui.elements.Element')
local Animator = lazy('harness.ui.Animator')
local Renderer = lazy('ui.markdown.Renderer')
local theme = lazy('harness.transcript.theme')
local PromptHistory = lazy('harness.ui.PromptHistory')
local AnswerDestination = lazy('harness.ui.AnswerDestination')
local PromptDestination = lazy('harness.ui.PromptDestination')
local composer_geometry = lazy('harness.ui.composer_geometry')

local ComposerView = Object:extend()

ComposerView.NAME = 'harness://composer'

ComposerView.NAMESPACE = Buffer.namespace('harness.composer')

ComposerView.FILETYPE = 'harness_composer'

ComposerView.WINDOWED = 30

ComposerView.MARGIN = 20

ComposerView.WINBAR = '%!v:lua.require\'harness.ui.composer\'.winbar()'

ComposerView.OMNIFUNC = 'v:lua.require\'harness.ui.composer\'.complete'

function ComposerView.has_text(lines)
  return vim.trim(table.concat(lines, '\n')) ~= ''
end

function ComposerView.warn(message)
  PromptDestination.warn(message)
end

function ComposerView.focus_window(win)
  local window = type(win) == 'number' and Window(win)

  if window and window:is_valid() then window:focus() end
end

function ComposerView.anchor_for(view)
  if not view then return nil end

  local tab = Window.current_tab()
  local candidates = { Window.get_current() }

  vim.list_extend(candidates, view:windows())

  for _, window in ipairs(candidates) do
    if
      window:is_valid()
      and window:get_tab() == tab
      and window:get_buffer().bufnr == view.bufnr
      and window:get_height() > composer_geometry.footprint()
    then
      return window
    end
  end
end

ComposerView.IDLE = {
  interrupt = function() end,
  model = function() end,
  slash = function()
    return '/'
  end,
  reference = function()
    return '@'
  end,
  accept = function(fallback)
    return fallback
  end,
  next_item = function(fallback)
    return fallback
  end,
  closed = function() end,
  wiped = function() end,
  entered = function() end,
}

function ComposerView:constructor(session, store, opts)
  opts = opts or {}

  local destination = opts.answering and AnswerDestination(session, store, opts.display, opts.answering)
    or PromptDestination(session, store, opts.display)

  return {
    session = session,
    store = store,
    display = opts.display,
    destination = destination,
    delegate = opts.delegate or ComposerView.IDLE,
    element = nil,
    anchor = nil,
    contained = nil,
    height = nil,
    origin = nil,
    source = {},
    recall = nil,
    shown = nil,
  }
end

function ComposerView:is_open()
  return self.element ~= nil and self.element:is_valid()
end

function ComposerView:lines()
  if not self:is_open() then return {} end

  return self.element:get_lines()
end

function ComposerView:focus(insert)
  self.element:focus()

  if insert then self.element:start_insert() end

  return self
end

function ComposerView:winbar()
  local session = self.session
  local title = (session.title or 'untitled'):gsub('%%', '%%%%')
  local anchored = self.anchor ~= nil and self.anchor:is_valid()
  local parts = {}

  if not anchored then
    parts[#parts + 1] = '%#UiTitle# ' .. session.key .. ' ' .. title .. ' %*'

    local mode = session:mode()

    if mode then
      parts[#parts + 1] = '%#UiAccent#' .. theme.MODE_FORMAT:format(mode.name or mode.id):gsub('%%', '%%%%') .. ' '
    end
  end

  if #session.queue > 0 then
    parts[#parts + 1] = string.format('%%#UiMuted#%s%d queued ', theme.QUEUE_ICON[1], #session.queue)
  end

  if session.external then parts[#parts + 1] = '%#UiWarn#⇄ also driven elsewhere: sending forks it ' end

  local answering = self.destination:label()

  if answering then
    parts[#parts + 1] = '%#UiWarn#' .. theme.WAITING_ICON[1] .. 'answering: ' .. answering:gsub('%%', '%%%%') .. ' '
  elseif #asks.asks_of(session) > 0 then
    parts[#parts + 1] = '%#UiWarn#' .. theme.WAITING_ICON[1] .. 'answer in the transcript '
  end

  for _, chunk in ipairs(self:hints()) do
    parts[#parts + 1] = '%#' .. chunk[2] .. '#' .. chunk[1]:gsub('%%', '%%%%')
  end

  parts[#parts + 1] = '%=%<'

  local written = self:lines()

  if ComposerView.has_text(written) then
    local chars = select(2, table.concat(written, '\n'):gsub('[^\128-\191]', ''))

    parts[#parts + 1] = string.format('%%#UiMuted#%dc %dl  ', chars, #written)
  end

  return table.concat(parts)
end

function ComposerView:hints()
  local session = self.session
  local keys = settings.keymaps:get('composer')
  local chunks = {}

  local function key(lhs, label)
    chunks[#chunks + 1] = { lhs, 'UiAccent' }
    chunks[#chunks + 1] = { ' ' .. label .. '  ', 'UiMuted' }
  end

  local inserting = self:is_open()
    and Window.get_current().win_id == self.element:get_window().win_id
    and Window.inserting()
  local send = inserting and ('<Esc>' .. keys.send) or keys.send

  self.destination:hints(key, { keys = keys, send = send, inserting = inserting })

  if #session.commands > 0 then key(keys.slash, 'commands') end
  if self.destination:history_hint() then key(keys.history, 'history') end
  if session:mode() then key(keys.cycle_mode, 'mode') end
  if not inserting and session:choice('model') then key(keys.model, 'model') end
  if not inserting then key(keys.close, 'close') end

  return chunks
end

function ComposerView:hints_text()
  return table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, self:hints()))
end

function ComposerView:refresh()
  local signature = self:hints_text()

  if signature ~= self.signature then
    self.signature = signature
    Window.redraw_bars()
  end

  return self
end

function ComposerView:placeholder()
  return self.destination:placeholder()
end

function ComposerView:_decorate()
  if not self:is_open() then return self end

  local buffer = self.element:get_buffer()

  buffer:clear_namespace(ComposerView.NAMESPACE)

  self.signature = self:hints_text()
  self.renderer = self.renderer or Renderer(buffer.bufnr)

  local drawn = self:lines()
  local first, last = 0, #drawn

  if #drawn > ComposerView.WINDOWED then
    local top, bottom = self.element:get_window():get_visible_range()

    first, last = math.max(top - ComposerView.MARGIN, 0), math.min(bottom + ComposerView.MARGIN, #drawn)
  end

  self.renderer:render(first, last)

  for row = first + 1, last do
    for _, found in ipairs(context.tokens(drawn[row])) do
      if context.names_file(found.token, self.session.dir) then
        buffer:set_extmark(ComposerView.NAMESPACE, row - 1, found.start - 1, {
          end_col = found.finish,
          hl_group = 'UiChip',
          priority = 200,
        })
      end
    end
  end

  if not ComposerView.has_text(self:lines()) then
    buffer:set_extmark(ComposerView.NAMESPACE, 0, 0, {
      virt_text = { { self:placeholder(), 'UiMuted' } },
      virt_text_pos = 'eol',
    })
  end

  return self
end

function ComposerView:_ease_open()
  local ms = settings.composer:get('ease_ms')
  local target = settings.composer:get('height')

  if ms <= 0 or target <= 1 or theme.reduced() then return self end

  local element = self.element
  local tween = motion.Tween({ from = 1, to = target, ms = ms, started = Timer.now() })

  element:set_height(1)

  self.animator = self.animator or Animator()
  self.animator:add('open', function(now)
    if not self:is_open() or self.closing then return false end

    element:set_height(math.max(1, math.floor(tween:at(now) + 0.5)))

    return not tween:done(now)
  end)

  return self
end

function ComposerView:attach(buf, range)
  if buf == self.element:get_buffer().bufnr or not Buffer.exists(buf) then return false end

  local buffer = Buffer(buf)
  local name = buffer:get_name()

  if name == '' or name:match('^%w+://') then return false, 'select lines in a file to reference them' end

  self:_insert(context.token(name, range))
  Window.redraw_bars()

  return true
end

function ComposerView:_insert(text)
  local cursor = self.element:get_cursor()
  local row, col = cursor[1], cursor[2]
  local line = self.element:get_lines()[row] or ''
  local before, after = line:sub(1, col), line:sub(col + 1)
  local lead = before ~= '' and before:sub(-1):match('%s') == nil and ' ' or ''
  local trail = (after == '' or after:sub(1, 1) ~= ' ') and ' ' or ''
  local skip = after:match('^%s+') or ''
  local written = lead .. text .. trail

  self.element:set_text(row - 1, col, written)
  self.element:set_cursor({ row, col + #lead + #text + #trail + #skip })
end

function ComposerView:_keep()
  if not self:is_open() then return self end

  self.element:set_buf_option('modified', false)

  if not self.destination:keeps_draft() then return self end

  local lines = self:lines()

  self.store:set_draft(self.session.key, ComposerView.has_text(lines) and lines or nil)

  return self
end

function ComposerView:_release()
  if self.contained then self.contained.dispose() end
  if self.group then self.group.dispose() end

  self.contained, self.group = nil, nil

  return self
end

function ComposerView:_contain(transcript_buf)
  local anchor = self.anchor

  if not anchor then return self end

  local function leave()
    Timer.schedule(function()
      if self:is_open() and not self.closing then self:close(false, { keep_focus = true }) end
    end)
  end

  self.contained = event.augroup('harness.composer.anchor.' .. self.session.key)
  self.contained.on('WinClosed', function(args)
    if tonumber(args.match) == anchor.win_id then leave() end
  end)
  self.contained.on('BufWinEnter', function()
    if anchor:is_valid() and anchor:get_buffer().bufnr ~= transcript_buf then leave() end
  end)
  self.contained.on('WinResized', function()
    Timer.schedule(function()
      if not (self:is_open() and anchor:is_valid()) or self.closing then return end

      local window = self.element:get_window()

      if window:is_below(anchor) then
        self.height = window:get_height()
      else
        window:place_below(anchor, self.height or settings.composer:get('height'))
      end
    end)
  end)

  return self
end

function ComposerView:close(discard, opts)
  local key = self.session.key

  self.closing = true
  self:_release()

  if self.animator then self.animator:close() end

  if not self.destination:keeps_draft() then
    self.destination:closing()

    discard = false
  end

  if self:is_open() then
    local lines = self.element:get_lines()
    local view = self.display and self.display.view_of(self.session)

    if self.destination:keeps_draft() then self.store:set_draft(key, ComposerView.has_text(lines) and lines or nil) end

    -- the transcript takes the rows back: put its top line back once it has grown
    if view then view:watch() end

    self.element:unmount()

    if view then view:hold_end() end
  elseif self.element and self.element:is_mounted() then
    -- the buffer went first (it is bufhidden=wipe), and the split it lived in
    -- did not: close that too
    self.element:unmount()
  end

  if discard then self.store:clear(key) end

  self.delegate.closed(self)

  if not (opts and opts.keep_focus) then ComposerView.focus_window(self.origin) end

  return self
end

function ComposerView:_outgoing()
  return { session = self.session, lines = self:lines(), source = self.source, origin = self.origin }
end

function ComposerView:_deliver(message, opts)
  return self.destination:submit(vim.trim(table.concat(message.lines, '\n')), message, opts)
end

function ComposerView:send(opts)
  local message = self:_outgoing()
  local sent, why = self:_deliver(message, opts)

  if not sent then return ComposerView.warn(why) end

  if self.display then self.display.reveal(message.session, message.origin, message.source) end

  self:close(true)

  return self
end

function ComposerView:_send_after_write()
  local message = self:_outgoing()

  Timer.schedule(function()
    local sent, why = self:_deliver(message)

    if not sent then
      if self.destination:keeps_draft() then self.store:set_draft(message.session.key, message.lines) end
      return ComposerView.warn(why)
    end

    if self.display then self.display.reveal(message.session, message.origin, message.source) end

    if self:is_open() then self:close(true) end
  end)

  return self
end

function ComposerView:restore(texts)
  local lines = vim.split(table.concat(texts, '\n\n'), '\n', { plain = true })
  local existing = self:is_open() and self:lines() or self.store:draft(self.session.key)

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

function ComposerView:_history()
  if not self.recall then self.recall = PromptHistory(PromptHistory.collect(self.session, self.store.sent)) end

  return self.recall
end

function ComposerView:_replace(text)
  local lines = vim.split(text, '\n', { plain = true })

  self.shown = text
  self.element:set_lines(lines)
  self.element:set_cursor({ #lines, #lines[#lines] })
end

function ComposerView:recall_step(direction)
  if self.destination:answers() then return false end

  local history = self:_history()
  local current = table.concat(self:lines(), '\n')

  if history:browsing() and current ~= self.shown then history:reset() end

  local text = direction < 0 and history:older(current) or history:newer()

  if not text then return false end

  self:_replace(text)

  return true
end

function ComposerView:pick_history()
  local entries = self:_history().entries

  if self.destination:answers() or #entries == 0 then return notice.info('no earlier prompts to recall') end

  local items = {}

  for i = #entries, 1, -1 do
    local lines = vim.split(entries[i], '\n', { plain = true })

    items[#items + 1] = {
      label = lines[1],
      description = #lines > 1 and string.format('+%d lines', #lines - 1) or nil,
      text = entries[i],
    }
  end

  surfaces.pick({
    title = 'Earlier prompts',
    items = items,
    width = '60vw',
    max_height = 15,
    on_select = function(item)
      Timer.schedule(function()
        if not self:is_open() then return end

        self:_replace(item.text)
        self:focus(true)
      end)
    end,
  })
end

function ComposerView:_edge(direction, passthrough)
  return function()
    local row = self.element:get_cursor()[1]
    local edge = direction < 0 and 1 or self.element:get_line_count()

    if row == edge and self:recall_step(direction) then return end

    keymap.feed(passthrough)
  end
end

function ComposerView:_bind_history(keys)
  local element = self.element

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, '<Up>', self:_edge(-1, '<Up>'), 'Earlier prompt on the first line')
    element:set_keymap(mode, '<Down>', self:_edge(1, '<Down>'), 'Later prompt on the last line')
    element:set_keymap(mode, keys.history, function()
      self:pick_history()
    end, 'Pick an earlier prompt')
  end

  element:set_keymap('n', keys.older, function()
    self:recall_step(-1)
  end, 'Earlier prompt')
  element:set_keymap('n', keys.newer, function()
    self:recall_step(1)
  end, 'Later prompt')

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
    self.delegate.interrupt(session)
  end, 'Interrupt the running turn')
  element:set_keymap('i', keys.interrupt, function()
    Window.stop_insert()
  end, 'Leave insert mode')

  for _, mode in ipairs({ 'n', 'i' }) do
    element:set_keymap(mode, keys.cycle_mode, function()
      session:cycle_mode()
    end, 'Next session mode')
  end

  element:set_keymap('n', keys.model, function()
    self.delegate.model(session, self.display)
  end, 'Session model')

  element:set_buf_var('completion', false)
  element:set_buf_option('omnifunc', ComposerView.OMNIFUNC)
  element:set_buf_option('completeopt', 'menuone,noinsert')
  element:set_keymap({ mode = 'i', key = keys.slash, desc = 'Slash commands', expr = true }, function()
    return self.delegate.slash()
  end)
  element:set_keymap({ mode = 'i', key = keys.reference, desc = 'Reference a file', expr = true }, function()
    return self.delegate.reference()
  end)
  element:set_keymap({ mode = 'i', key = '<CR>', desc = 'Take the completion', expr = true }, function()
    return self.delegate.accept('<CR>')
  end)
  element:set_keymap({ mode = 'i', key = '<Tab>', desc = 'Next completion', expr = true }, function()
    return self.delegate.next_item('<Tab>')
  end)

  element:set_keymap('n', keys.close, function()
    self:close()
  end, 'Close (keeps the draft)')
  return self:_bind_history(keys)
end

function ComposerView:_listen()
  local element = self.element

  element:attach_to_changes({
    on_lines = function()
      Timer.schedule(function()
        self:_keep():_decorate()
      end)
    end,
  })

  element:on('QuitPre', function()
    self:_keep()
  end)

  element:on('BufEnter', function()
    self.delegate.entered(self)
  end)

  self.group = event.augroup('harness.composer.view.' .. self.session.key)
  self.group.on('ModeChanged', function()
    if self:is_open() then self:refresh() end
  end)
  self.group.on('WinScrolled', function()
    if self:is_open() and #self:lines() > ComposerView.WINDOWED then self:_decorate() end
  end)
  self.group.on('WinResized', function()
    Timer.defer(0, function()
      if self:is_open() then self:_decorate() end
    end)
  end)

  element:on('BufWriteCmd', function()
    element:set_buf_option('modified', false)

    if self:is_open() then self:_send_after_write() end
  end)

  element:on('BufWipeout', function()
    self:_release()

    -- The buffer went on its own (it is bufhidden=wipe): switching buffers in
    -- the composer window, as <C-l> does, is the usual way. The split must go
    -- with it, or it is left showing whatever buffer replaced the composer.
    if not self.closing and self.element and self.element:is_mounted() then
      local element = self.element

      -- closing the window inside BufWipeout is too early; the buffer switch
      -- that caused it is still running
      Timer.defer(0, function()
        if element:is_mounted() then element:forget() end
      end)
    end

    self.delegate.wiped(self)
  end)

  return self
end

function ComposerView:mount(insert)
  local session = self.session
  local view = self.display and self.display.view_of(session)
  local anchor = ComposerView.anchor_for(view)
  local element = Element({
    buf_options = {
      buftype = 'acwrite',
      bufhidden = 'wipe',
      swapfile = false,
      buflisted = false,
      filetype = ComposerView.FILETYPE,
    },
    win_options = {
      winbar = ComposerView.WINBAR,
      winfixheight = true,
      wrap = true,
      linebreak = true,
      conceallevel = 2,
      concealcursor = '',
      number = false,
      relativenumber = false,
      signcolumn = 'no',
      winhl = 'Normal:UiComposer,EndOfBuffer:UiComposer',
    },
    win_plot = { split = 'below', win = anchor and anchor.win_id or -1, height = settings.composer:get('height') },
  })

  self.anchor = anchor
  self.origin = Window.get_current().win_id
  self.source = { win = view and view.source_win, buf = view and view.source_buf }
  self.element = element

  -- the split takes rows from the transcript: note where the reader is first,
  -- then put the top line back once the window has shrunk
  if view then view:watch() end

  element:mount()

  if view then view:hold_end() end

  self:_ease_open()

  element:set_name(ComposerView.NAME .. '/' .. session.key)
  local draft = (self.destination:keeps_draft() and self.store:draft(session.key)) or { '' }

  element:set_lines(draft)
  element:set_buf_option('modified', false)
  element:focus()
  element:set_cursor({ element:get_line_count(), #(element:get_lines()[element:get_line_count()] or '') })

  self:_bind(settings.keymaps:get('composer')):_listen():_decorate()
  self:_contain(view and view.bufnr)

  if insert then element:start_insert() end

  return self
end

return ComposerView

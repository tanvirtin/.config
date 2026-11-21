local fs = require('core.system.fs')
local Lens = require('ui.Lens')
local Timer = require('core.Timer')
local lsp = require('core.editor.lsp')
local Window = require('core.editor.Window')
local console = require('core.console')
local compact = require('compact')
local Element = require('ui.elements.Element')
local Surface = require('surfaces.Surface')
local Renderer = require('ui.markdown.Renderer')

local InfoLens = Surface:extend()

InfoLens.MAX_HOVER = 8

InfoLens.MAX_REFS = 5

InfoLens.MAX_ROWS = 15

InfoLens.WAIT_MS = 2000

function InfoLens:constructor(opts)
  local window = opts.window or Window.get_current()
  local instance = Surface.constructor(self, { kind = 'info', title = window:get_word(), owner = opts.owner })

  instance._window = window
  instance._line = opts.line or window:get_cursor()[1]
  instance._composed = nil
  instance._lens = nil
  instance._element = nil
  instance._contained = nil
  instance._arrived = false

  return instance
end

function InfoLens.compose(hover, refs)
  local lines, targets = {}, {}

  for i = 1, math.min(#hover, InfoLens.MAX_HOVER) do
    lines[#lines + 1] = hover[i]
  end

  if #hover > InfoLens.MAX_HOVER then lines[#lines + 1] = '…' end
  if #hover == 0 then lines[#lines + 1] = '*No hover information*' end

  lines[#lines + 1] = ''

  if #refs == 0 then
    lines[#lines + 1] = '*Not used anywhere else*'
  else
    lines[#lines + 1] = string.format('**Used in %d place%s**', #refs, #refs == 1 and '' or 's')

    for i = 1, math.min(#refs, InfoLens.MAX_REFS) do
      lines[#lines + 1] = string.format('- %s:%d', fs.display(refs[i].path), refs[i].line)
      targets[#lines] = refs[i]
    end

    if #refs > InfoLens.MAX_REFS then lines[#lines + 1] = string.format('… %d more', #refs - InfoLens.MAX_REFS) end
  end

  return { lines = lines, targets = targets }
end

local function first_hover(results)
  for _, response in pairs(results or {}) do
    local result = response.result

    if result and result.contents then return lsp.markdown_lines(result.contents) end
  end

  return {}
end

local function references(results)
  local seen, refs = {}, {}

  for client_id, response in pairs(results or {}) do
    local client = lsp.client(client_id)

    if response.result and client then
      for _, entry in ipairs(lsp.locations_to_items(response.result, client.offset_encoding)) do
        local key = entry.filename .. ':' .. entry.lnum

        if not seen[key] then
          seen[key] = true
          refs[#refs + 1] = { path = entry.filename, line = entry.lnum }
        end
      end
    end
  end

  table.sort(refs, function(a, b)
    if a.path ~= b.path then return a.path < b.path end

    return a.line < b.line
  end)

  return refs
end

local function ask(window, method, extend, handler)
  local bufnr = window:get_buffer().bufnr

  window:call(function()
    lsp.request_all(bufnr, method, function(client)
      local params = lsp.position_params(client.offset_encoding)

      if extend then extend(params) end

      return params
    end, handler)
  end)
end

function InfoLens:begin()
  local window = self._window

  if #lsp.clients({ bufnr = window:get_buffer().bufnr }) == 0 then
    console.notify_now('Info lens: no language server is attached to this buffer', 'info')

    return self:close()
  end

  local hover, refs, pending = {}, {}, 2

  local function arrive()
    pending = pending - 1

    if pending == 0 then self:_ready(hover, refs) end
  end

  self:set_state('loading')

  ask(window, 'textDocument/hover', nil, function(results)
    hover = first_hover(results)
    arrive()
  end)

  ask(window, 'textDocument/references', function(params)
    params.context = { includeDeclaration = false }
  end, function(results)
    refs = references(results)
    arrive()
  end)

  Timer.defer(InfoLens.WAIT_MS, function()
    if pending > 0 then
      pending = 0
      self:_ready(hover, refs)
    end
  end)

  return self
end

function InfoLens:_ready(hover, refs)
  if self._arrived or self.state == 'closed' then return end

  self._arrived = true

  if not self._window:is_valid() then return self:close() end

  self._composed = InfoLens.compose(hover, refs)

  local height = math.min(#self._composed.lines, InfoLens.MAX_ROWS)

  if not Lens.fits(self._window, height + Lens.CHROME_ROWS) then
    require('surfaces').panel({ title = self.title, lines = self._composed.lines })

    return self:close()
  end

  return self:open()
end

function InfoLens:open()
  local window = self._window
  local height = math.min(#self._composed.lines, InfoLens.MAX_ROWS)
  local lens = Lens(window, self._line)

  lens:reserve(height)

  local element = Element({
    buf_options = { buftype = 'nofile', bufhidden = 'wipe', swapfile = false, buflisted = false },
    window_mode = 'floating',
    win_options = {
      wrap = true,
      linebreak = true,
      conceallevel = 2,
      concealcursor = 'nc',
      number = false,
      relativenumber = false,
      signcolumn = 'no',
      cursorline = false,
      winhl = 'Normal:UiComposer,EndOfBuffer:UiComposer',
    },
    win_plot = lens:plot(height),
  })

  self._lens, self._element = lens, element
  element:mount()
  element:set_lines(self._composed.lines)
  element:set_buf_option('modifiable', false)
  Renderer(element:get_buffer().bufnr):render(0)

  lens:header(Lens.band({
    { ' ' .. self.title .. ' ', 'UiTitle' },
    { ' ', nil },
    { '<CR>', 'UiAccent' },
    { ' open  ', 'UiMuted' },
    { 'q', 'UiAccent' },
    { ' close ', 'UiMuted' },
  }))

  for _, key in ipairs({ 'q', '<Esc>' }) do
    element:set_keymap('n', key, function()
      self:close()
    end, 'Close')
  end

  element:set_keymap('n', '<CR>', function()
    self:_open_under_cursor()
  end, 'Open the reference under the cursor')

  self._contained = lens:follow(self.id, element, function()
    Timer.schedule(function()
      if self:is_open() then self:close() end
    end)
  end)

  element:focus()
  Timer.schedule(function()
    if self:is_open() and not element:is_focused() then element:focus() end
  end)
  self:set_state('ready')

  return self
end

function InfoLens:_open_under_cursor()
  local target = self._composed.targets[self._element:get_cursor()[1]]

  if not target then return end

  local origin = self._window.win_id

  self:close()
  require('surfaces').jump(target, 'edit', origin)
end

function InfoLens:is_open()
  return self._element ~= nil and self._element:is_valid()
end

function InfoLens:close()
  local was_open = self:is_open()

  if self._contained then self._contained.dispose() end
  if self._element then self._element:unmount() end

  self._contained, self._element, self._lens = nil, nil, nil

  if was_open and self._window:is_valid() then self._window:focus() end

  self:set_state('closed')
  self:emit('close')

  return self
end

function InfoLens:snapshot(budget)
  local lines = self._composed and self._composed.lines or {}

  return string.format('%s: info lens "%s" [%s]\n', self.id, self.title, self.state)
    .. compact.text(table.concat(lines, '\n'), budget or compact.BUDGET)
end

return InfoLens

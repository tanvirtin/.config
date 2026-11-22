local lazy = require('core.lazy')

local event = lazy('core.event')
local Object = lazy('core.Object')
local layer = lazy('ui.design.layer')
local Buffer = lazy('core.editor.Buffer')

local Lens = Object:extend()

Lens.NAMESPACE = Buffer.namespace('ui.lens')

Lens.MIN_WIDTH = 40

Lens.ROOM = 4

Lens.CHROME_ROWS = 1

Lens.BAND = 'UiComposer'

Lens.BAND_FILL = 300

function Lens.band(chunks)
  local out = {}

  for _, chunk in ipairs(chunks) do
    out[#out + 1] = { chunk[1], { Lens.BAND, chunk[2] } }
  end

  out[#out + 1] = { string.rep(' ', Lens.BAND_FILL), Lens.BAND }

  return out
end

function Lens.fits(window, rows)
  if not window or not window:is_valid() or window:is_floating() then return false end
  if window:get_buffer():get_option('buftype') ~= '' then return false end

  return window:get_height() >= rows + Lens.ROOM and window:get_text_width() >= Lens.MIN_WIDTH
end

function Lens:constructor(window, line)
  return {
    window = window,
    buffer = window:get_buffer(),
    line = line,
    side = nil,
    mark = nil,
    rows = nil,
    title = nil,
    body = nil,
  }
end

function Lens:_draw()
  local lines = { self.title or { { '' } } }

  for i = 1, self.rows - Lens.CHROME_ROWS do
    lines[#lines + 1] = self.body and self.body[i] or { { '' } }
  end

  self.mark = self.buffer:set_extmark(Lens.NAMESPACE, self:current() - 1, 0, {
    id = self.mark,
    virt_lines = lines,
    virt_lines_above = self.side == 'above',
    priority = layer.of('mark'),
  })

  return self
end

function Lens:reserve(height)
  local window = self.window

  self.rows = height + Lens.CHROME_ROWS

  if self.line > 1 and window:get_view().topline >= self.line then window:scroll_up(1) end

  self.side = (self.line > 1 and window:get_view().topline < self.line) and 'above' or 'below'

  return self:_draw()
end

function Lens:header(chunks, body)
  self.title = chunks

  if body then self.body = body end

  return self:_draw()
end

function Lens:current()
  local row = self.mark and self.buffer:get_extmark_row(Lens.NAMESPACE, self.mark)

  return (row or self.line - 1) + 1
end

function Lens:config()
  local window = self.window
  local text = window:get_text_width()
  local above = self.side == 'above'

  return {
    relative = 'win',
    win = window.win_id,
    bufpos = { self:current() - 1, 0 },
    anchor = above and 'SW' or 'NW',
    row = above and 0 or 1 + Lens.CHROME_ROWS,
    col = 0,
    width = math.max(text, Lens.MIN_WIDTH),
  }
end

function Lens:plot(height)
  return vim.tbl_extend('force', self:config(), {
    height = height,
    border = 'none',
    focus = true,
  })
end

function Lens:request()
  return { win = self.window.win_id, line = self:current() }
end

function Lens:matches(request)
  return request ~= nil and request.win == self.window.win_id and request.line == self:current()
end

function Lens:release()
  if self.mark then self.buffer:del_extmark(Lens.NAMESPACE, self.mark) end

  self.mark = nil

  return self
end

function Lens:follow(key, element, leave)
  local window = self.window
  local group = event.augroup('ui.lens.' .. key)

  local function reposition()
    if element and window:is_valid() and element:is_valid() then element:get_window():set_config(self:config()) end
  end

  group.on('WinClosed', function(args)
    if tonumber(args.match) == window.win_id then leave() end
  end)
  group.on('BufWinEnter', function()
    if window:is_valid() and window:get_buffer().bufnr ~= self.buffer.bufnr then leave() end
  end)
  group.on({ 'WinScrolled', 'VimResized', 'TextChanged', 'TextChangedI' }, reposition)

  return {
    dispose = function()
      group.dispose()
      self:release()
    end,
  }
end

return Lens

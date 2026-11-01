local Buffer = require('core.Buffer')
local Object = require('core.Object')
local Window = require('core.Window')
local buffers = require('core.buffers')
local settings = require('harness.settings')

local TourView = Object:extend()

TourView.TRACK = Buffer.namespace('harness.tour.track')
TourView.SHOW = Buffer.namespace('harness.tour.show')
TourView.PRIORITY = 90
TourView.HARNESS_PREFIX = 'harness://'

function TourView:constructor(tour, opts)
  opts = opts or {}

  return {
    tour = tour,
    index = 0,
    source = opts.source_win,
    window = nil,
    note = nil,
    note_buffer = nil,
    anchors = {},
    bound = {},
    shown = {},
    on_stop = opts.on_stop,
    stopped = false,
  }
end

function TourView:is_open()
  return self.index > 0
end

function TourView:_foreign(window)
  if not window:is_valid() or window:get_config().relative ~= '' then return false end

  return window:get_buffer():get_name():sub(1, #TourView.HARNESS_PREFIX) ~= TourView.HARNESS_PREFIX
end

function TourView:_code_window()
  if self.window and self:_foreign(self.window) then return self.window end

  if self.source then
    local source = Window(self.source)

    if self:_foreign(source) then return source end
  end

  for _, window in ipairs(Window.list_tab()) do
    if self:_foreign(window) then return window end
  end

  return nil
end

function TourView:_range(index, buffer)
  local step = self.tour.steps[index]
  local last = buffer:get_line_count()
  local anchor = self.anchors[index]
  local first, finish = step.line - 1, step.end_line - 1

  if anchor and anchor.bufnr == buffer.bufnr then
    local row, end_row = buffer:get_extmark_range(TourView.TRACK, anchor.id)

    if row then
      first, finish = row, math.max(end_row, row)
    end
  end

  first = math.min(first, last - 1)

  return first, math.min(math.max(finish, first), last - 1)
end

function TourView:_track(index, buffer, first, finish)
  local anchor = self.anchors[index]

  if anchor and anchor.bufnr == buffer.bufnr then return end

  local id = buffer:set_extmark(TourView.TRACK, first, 0, { end_row = finish, end_col = 0, right_gravity = false })

  self.anchors[index] = { bufnr = buffer.bufnr, id = id }
end

function TourView:_clear()
  for bufnr in pairs(self.shown) do
    Buffer(bufnr):clear_namespace(TourView.SHOW)
  end

  self.shown = {}
end

function TourView:_mark(index, buffer, first, finish)
  local step = self.tour.steps[index]
  local label = string.format(' %d/%d%s ', index, #self.tour.steps, step.title and (' · ' .. step.title) or '')

  buffer:set_extmark(TourView.SHOW, first, 0, {
    end_row = finish + 1,
    end_col = 0,
    hl_group = 'UiSurfaceAccent',
    hl_eol = true,
    priority = TourView.PRIORITY,
  })
  buffer:set_extmark(TourView.SHOW, first, 0, {
    virt_text = { { label, 'UiSurfaceRaised' } },
    virt_text_pos = 'right_align',
    priority = TourView.PRIORITY,
  })
  self.shown[buffer.bufnr] = true
end

function TourView:_keys()
  local keys = settings.keymaps:get('tour')

  return {
    { keys.next, 'next', 'Next step of the tour' },
    { keys.previous, 'previous', 'Previous step of the tour' },
    { keys.stop, 'stop', 'End the tour' },
  }
end

function TourView:_bind(buffer)
  if self.bound[buffer.bufnr] then return end

  self.bound[buffer.bufnr] = true

  for _, key in ipairs(self:_keys()) do
    buffer:set_keymap({ key = key[1], mode = 'n', desc = key[3] }, function()
      self[key[2]](self)
    end)
  end
end

function TourView:_unbind()
  for bufnr in pairs(self.bound) do
    if Buffer.exists(bufnr) then
      for _, key in ipairs(self:_keys()) do
        Buffer(bufnr):del_keymap({ key = key[1], mode = 'n' })
      end
    end
  end

  self.bound = {}
end

function TourView:_note_lines(index)
  local step = self.tour.steps[index]
  local lines = {}

  if index == 1 and self.tour.summary then
    vim.list_extend(lines, vim.split(self.tour.summary, '\n', { plain = true }))
    vim.list_extend(lines, { '', '---', '' })
  end

  vim.list_extend(lines, vim.split(step.note ~= '' and step.note or (step.title or ''), '\n', { plain = true }))

  return lines
end

function TourView:_close_note()
  if self.note and self.note:is_valid() then self.note:close() end

  self.note, self.note_buffer = nil, nil
end

function TourView:_show_note(window, index, first)
  self:_close_note()

  local spec = settings.tour
  local keys = settings.keymaps:get('tour')
  local step = self.tour.steps[index]
  local lines = self:_note_lines(index)
  local width = math.max(math.floor(window:get_width() * spec:get('note_width')), spec:get('note_min_width'))
  local top, bottom = window:get_visible_range()
  local lower = (first + 1 - top) / math.max(bottom - top, 1) > 0.5
  local buffer = Buffer():create(false, true)

  width = math.min(width, math.max(window:get_width() - 2, 10))
  buffer:set_lines(lines)
  buffer:set_option('filetype', 'markdown')
  buffer:set_option('bufhidden', 'wipe')

  self.note = window:open(buffer, {
    relative = 'win',
    win = window.win_id,
    anchor = lower and 'NE' or 'SE',
    row = lower and 0 or window:get_height(),
    col = window:get_width(),
    width = width,
    height = 1,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    zindex = 60,
    title = string.format(' %d/%d%s ', index, #self.tour.steps, step.title and (' · ' .. step.title) or ''),
    title_pos = 'left',
    footer = string.format(' %s next · %s back · %s end ', keys.next, keys.previous, keys.stop),
    footer_pos = 'right',
  })
  self.note_buffer = buffer
  self.note:assign_options({
    wrap = true,
    linebreak = true,
    conceallevel = 2,
    winhl = 'Normal:UiComposer,FloatBorder:UiMuted,FloatTitle:UiTitle,FloatFooter:UiMuted',
  })
  self.note:set_height(math.max(1, math.min(self.note:get_text_height(1, #lines), spec:get('note_max_height'))))
end

function TourView:show(index)
  local step = self.tour.steps[index]

  if not step then return false end

  local window = self:_code_window()

  if not window then return false, 'no window to show the code in' end

  local buffer = buffers.load(step.path)

  self:_clear()

  if window:get_buffer().bufnr ~= buffer.bufnr then window:set_buffer(buffer) end

  local first, finish = self:_range(index, buffer)

  self:_track(index, buffer, first, finish)
  self:_mark(index, buffer, first, finish)
  self:_bind(buffer)

  window:set_cursor({ first + 1, 0 })
  window:scroll_to('center')

  self.window = window
  self.index = index
  self:_show_note(window, index, first)

  return true
end

function TourView:start()
  local window = self:_code_window()

  if window then window:focus() end

  return self:show(1)
end

function TourView:next()
  if self.index >= #self.tour.steps then return self:stop() end

  return self:show(self.index + 1)
end

function TourView:previous()
  return self:show(math.max(self.index - 1, 1))
end

function TourView:stop()
  if self.stopped then return false end

  self.stopped = true
  self:_clear()
  self:_close_note()
  self:_unbind()

  for _, anchor in pairs(self.anchors) do
    if Buffer.exists(anchor.bufnr) then Buffer(anchor.bufnr):del_extmark(TourView.TRACK, anchor.id) end
  end

  self.anchors, self.index = {}, 0

  if self.on_stop then self.on_stop(self) end

  return true
end

return TourView

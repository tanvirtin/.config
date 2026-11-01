local fs = require('core.fs')
local Timer = require('core.Timer')
local event = require('core.event')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local Window = require('core.Window')
local buffers = require('core.buffers')
local settings = require('harness.settings')
local tour_scope = require('harness.tour_scope')

local TourView = Object:extend()

local instances = 0

TourView.TRACK = Buffer.namespace('harness.tour.track')
TourView.SHOW = Buffer.namespace('harness.tour.show')
TourView.PRIORITY = 90
TourView.HARNESS_PREFIX = 'harness://'

function TourView:constructor(tour, opts)
  opts = opts or {}

  instances = instances + 1

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
    session = opts.session,
    snapshots = {},
    on_stop = opts.on_stop,
    on_ask = opts.on_ask,
    group = event.augroup('harness.tour.' .. instances),
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

function TourView:_open_above(buffer)
  local base = self.source and Window(self.source) or nil

  if not (base and base:is_valid() and base:get_config().relative == '') then
    base = nil

    for _, window in ipairs(Window.list_tab()) do
      if window:get_config().relative == '' then
        base = window
        break
      end
    end
  end

  return base and base:split_above(buffer) or nil
end

function TourView:_buffer(step)
  local tour = self.tour

  if not tour.rev then return buffers.load(step.path) end

  local cached = self.snapshots[step.path]

  if cached and cached:is_valid() then return cached end

  local relative = fs.make_relative(tour.root, step.path)
  local lines = tour_scope.show(tour.root, tour.rev, relative)
    or { string.format('(%s is not in %s)', relative, tour.rev:sub(1, 7)) }

  if lines[#lines] == '' then lines[#lines] = nil end

  local buffer = Buffer():create(false, true)

  buffer:set_name(string.format('rev://%s/%s', tour.rev:sub(1, 7), relative))
  buffer:set_lines(lines)
  buffer:set_option('filetype', fs.detect_filetype(step.path) or '')
  buffer:set_option('modifiable', false)
  buffer:set_option('bufhidden', 'hide')

  self.snapshots[step.path] = buffer

  return buffer
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
  local label = string.format(
    ' %d/%d%s%s ',
    index,
    #self.tour.steps,
    step.title and (' · ' .. step.title) or '',
    self.tour.rev and (' @' .. self.tour.rev:sub(1, 7)) or ''
  )

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
    { keys.ask, 'ask', 'Ask about this step' },
  }
end

function TourView:_bind(buffer)
  if self.bound[buffer.bufnr] then return end

  self.bound[buffer.bufnr] = true

  self.group.on({ 'BufDelete', 'BufWipeout' }, function()
    Timer.defer(0, function()
      if not self.stopped and self:is_open() then self:stop() end
    end)
  end, { buffer = buffer })

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

  local buffer = self:_buffer(step)
  local window = self:_code_window() or self:_open_above(buffer)

  if not window then return false, 'no window to show the code in' end

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

function TourView:ask()
  if self.on_ask then self.on_ask(self) end
end

function TourView:step()
  return self.tour.steps[self.index], self.index
end

function TourView:_step_for(path)
  if type(path) ~= 'string' or path == '' then return nil end

  local root = self.tour.root
  local relative

  if root and path:sub(1, 6) == 'rev://' then relative = path:match('^rev://[^/]+/(.+)$') end

  local found

  for index, step in ipairs(self.tour.steps) do
    local matches = relative and fs.make_relative(root, step.path) == relative
      or (not relative and fs.normalize(step.path) == fs.normalize(path))

    if matches then
      if index == self.index then return index end

      found = found or index
    end
  end

  return found
end

function TourView:select(path, first, last)
  if not self:is_open() then return false end

  local index = self:_step_for(path)

  if not index then return false end

  local step = self.tour.steps[index]

  step.line = math.max(math.floor(first or step.line), 1)
  step.end_line = math.max(math.floor(last or step.line), step.line)

  self:_forget(index)

  return self:show(index)
end

function TourView:_forget(from)
  for index = #self.tour.steps, from, -1 do
    local anchor = self.anchors[index]

    if anchor and Buffer.exists(anchor.bufnr) then Buffer(anchor.bufnr):del_extmark(TourView.TRACK, anchor.id) end

    self.anchors[index] = nil
  end
end

function TourView:insert(steps)
  local at, count = self.index, #steps

  for index = #self.tour.steps, at + 1, -1 do
    self.anchors[index + count] = self.anchors[index]
    self.anchors[index] = nil
  end

  for offset, step in ipairs(steps) do
    table.insert(self.tour.steps, at + offset, step)
  end

  return self:show(at + 1)
end

function TourView:replace_rest(steps)
  self:_forget(self.index + 1)

  for index = #self.tour.steps, self.index + 1, -1 do
    table.remove(self.tour.steps, index)
  end

  vim.list_extend(self.tour.steps, steps)

  return self:show(math.min(self.index + 1, #self.tour.steps))
end

function TourView:annotate(note)
  self.tour.steps[self.index].note = note

  return self:show(self.index)
end

TourView.MODE = { insert = 'insert', replace = 'replace', note = 'note' }

function TourView:apply(update)
  if not self:is_open() then return false, 'the tour is not showing' end

  if update.mode == TourView.MODE.note then return self:annotate(update.note or '') end
  if update.mode == TourView.MODE.replace then return self:replace_rest(update.steps or {}) end

  return self:insert(update.steps or {})
end

function TourView:start(index)
  local ok, why = self:show(index or 1)

  if ok then self.window:focus() end

  return ok, why
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
  self.last_index = self.index

  self:_clear()
  self:_close_note()
  self:_unbind()

  self:_forget(1)

  for _, snapshot in pairs(self.snapshots) do
    if snapshot:is_valid() then snapshot:delete() end
  end

  self.snapshots, self.anchors, self.index = {}, {}, 0

  if self.group then self.group.dispose() end

  if self.on_stop then self.on_stop(self) end

  return true
end

return TourView

local fs = require('core.fs')
local Timer = require('core.Timer')
local event = require('core.event')
local vgit = require('harness.vgit')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local Window = require('core.Window')
local keymap = require('core.keymap')
local buffers = require('core.buffers')
local Panel = require('surfaces.Panel')
local settings = require('harness.settings')
local Renderer = require('ui.markdown.Renderer')
local walkthrough_scope = require('harness.walkthrough_scope')
local walkthrough_overview = require('harness.walkthrough_overview')

local WalkthroughView = Object:extend()

local instances = 0

WalkthroughView.TRACK = Buffer.namespace('harness.walkthrough.track')
WalkthroughView.SHOW = Buffer.namespace('harness.walkthrough.show')
WalkthroughView.PRIORITY = 90
WalkthroughView.HARNESS_PREFIX = 'harness://'
WalkthroughView.BAR = '▎'
WalkthroughView.WRITING = '_Writing a note…_'
WalkthroughView.LAYOUT = { unified = 'unified', split = 'split' }

function WalkthroughView:constructor(walkthrough, opts)
  opts = opts or {}

  instances = instances + 1

  return {
    id = instances,
    walkthrough = walkthrough,
    index = 0,
    started = false,
    overviewing = false,
    targets = {},
    part = 1,
    source = opts.source_win,
    window = nil,
    split = nil,
    note = nil,
    note_buffer = nil,
    anchors = {},
    bound = {},
    scroll_bound = {},
    shown = {},
    seen = {},
    session = opts.session,
    snapshots = {},
    bases = {},
    on_stop = opts.on_stop,
    on_ask = opts.on_ask,
    write_note = opts.write_note,
    note_errors = {},
    group = event.augroup('harness.walkthrough.' .. instances),
    stopped = false,
  }
end

function WalkthroughView:is_open()
  return self.started and not self.stopped
end

function WalkthroughView.ranges(step)
  return step.ranges and #step.ranges > 0 and step.ranges or { step }
end

function WalkthroughView:_foreign(window)
  if not window:is_valid() or window:get_config().relative ~= '' then return false end
  if self.split and window:is_same(self.split) then return false end

  return window:get_buffer():get_name():sub(1, #WalkthroughView.HARNESS_PREFIX) ~= WalkthroughView.HARNESS_PREFIX
end

function WalkthroughView:_code_window()
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

function WalkthroughView:_open_beside(buffer)
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

  if not base then return nil end

  local window = base:split_left(buffer)

  if not window then return nil end

  local spec = settings.transcript
  local total = window:get_width() + base:get_width()

  base:set_width(math.max(spec:get('tile_min_width'), math.floor(total * spec:get('tile_width'))))

  return window
end

function WalkthroughView:_snapshot(key, name, lines, path)
  local cached = self.snapshots[key]

  if cached and cached:is_valid() then return cached end

  if lines[#lines] == '' then lines[#lines] = nil end

  local buffer = Buffer():create(false, true)

  buffer:set_name(name)
  buffer:set_lines(lines)
  buffer:set_option('filetype', fs.detect_filetype(path) or '')
  buffer:set_option('modifiable', false)
  buffer:set_option('bufhidden', 'hide')

  self.snapshots[key] = buffer

  return buffer
end

function WalkthroughView:_buffer(path)
  local walkthrough = self.walkthrough

  if not walkthrough.rev then return buffers.load(path) end

  local relative = fs.make_relative(walkthrough.root, path)
  local lines = walkthrough_scope.show(walkthrough.root, walkthrough.rev, relative)
    or { string.format('(%s is not in %s)', relative, walkthrough.rev:sub(1, 7)) }

  return self:_snapshot(path, string.format('rev://%s/%s', walkthrough.rev:sub(1, 7), relative), lines, path)
end

function WalkthroughView:_base_path(path)
  local walkthrough = self.walkthrough

  if walkthrough.scope then return walkthrough_scope.base_path(walkthrough.scope, path) end

  return fs.make_relative(walkthrough.root, path)
end

function WalkthroughView:_base_lines(path)
  local walkthrough = self.walkthrough

  if not (walkthrough.base and walkthrough.root) then return nil end

  local cached = self.bases[path]

  if cached then return cached end

  local lines = walkthrough_scope.show(walkthrough.root, walkthrough.base, self:_base_path(path)) or {}

  if lines[#lines] == '' then lines[#lines] = nil end

  self.bases[path] = lines

  return lines
end

function WalkthroughView:_base_buffer(path)
  return self:_snapshot(
    'base:' .. path,
    string.format('rev://%s/%s', self.walkthrough.base:sub(1, 7), self:_base_path(path)),
    vim.list_extend({}, self:_base_lines(path)),
    path
  )
end

function WalkthroughView:_layout(window)
  local spec = settings.walkthrough

  if
    vgit.layout(spec:get('diff_layout')) == WalkthroughView.LAYOUT.split
    and window:get_width() >= spec:get('split_min_width')
  then
    return WalkthroughView.LAYOUT.split
  end

  return WalkthroughView.LAYOUT.unified
end

function WalkthroughView:_range(index, part, buffer)
  local range = WalkthroughView.ranges(self.walkthrough.steps[index])[part]
  local last = buffer:get_line_count()
  local anchor = self.anchors[index] and self.anchors[index][part]
  local first, finish = range.line - 1, range.end_line - 1

  if anchor and anchor.bufnr == buffer.bufnr then
    local row, end_row = buffer:get_extmark_range(WalkthroughView.TRACK, anchor.id)

    if row then
      first, finish = row, math.max(end_row, row)
    end
  end

  first = math.min(first, last - 1)

  return first, math.min(math.max(finish, first), last - 1)
end

function WalkthroughView:_track(index, part, buffer, first, finish)
  local anchors = self.anchors[index] or {}
  local anchor = anchors[part]

  self.anchors[index] = anchors

  if anchor and anchor.bufnr == buffer.bufnr then return end

  local id =
    buffer:set_extmark(WalkthroughView.TRACK, first, 0, { end_row = finish, end_col = 0, right_gravity = false })

  anchors[part] = { bufnr = buffer.bufnr, id = id }
end

function WalkthroughView:_clear()
  for bufnr in pairs(self.shown) do
    if Buffer.exists(bufnr) then Buffer(bufnr):clear_namespace(WalkthroughView.SHOW) end
  end

  self.shown = {}
end

function WalkthroughView:_mark(buffer, first, finish, label, diffed)
  if diffed then
    for row = first, finish do
      buffer:set_extmark(WalkthroughView.SHOW, row, 0, {
        sign_text = WalkthroughView.BAR,
        sign_hl_group = 'UiAccent',
        priority = WalkthroughView.PRIORITY,
      })
    end
  else
    buffer:set_extmark(WalkthroughView.SHOW, first, 0, {
      end_row = finish + 1,
      end_col = 0,
      hl_group = 'UiSurfaceAccent',
      hl_eol = true,
      priority = WalkthroughView.PRIORITY,
    })
  end

  buffer:set_extmark(WalkthroughView.SHOW, first, 0, {
    virt_text = { { label, 'UiSurfaceRaised' } },
    virt_text_pos = 'right_align',
    priority = WalkthroughView.PRIORITY,
  })
  self.shown[buffer.bufnr] = true
end

local function removed_lines(hunk, width, tabstop)
  local out = {}
  local tab = string.rep(' ', tabstop)

  for _, line in ipairs(hunk.diff or {}) do
    if line:sub(1, 1) == '-' then
      local text = line:sub(2):gsub('\t', tab)

      out[#out + 1] = { { text .. string.rep(' ', math.max(width - #text, 0)), vgit.BACKGROUND_HL.remove } }
    end
  end

  return out
end

function WalkthroughView:_draw_diff(buffer, window, path)
  local old = self:_base_lines(path)

  if not old then return nil end

  local hunks = vgit.hunks(old, buffer:get_lines())
  local width = window:get_width()
  local tabstop = buffer:get_option('tabstop')
  local last = buffer:get_line_count()

  for _, hunk in ipairs(hunks) do
    local removed = removed_lines(hunk, width, tabstop)

    if hunk.type == 'remove' then
      if #removed > 0 then
        local above = hunk.top < 1

        buffer:set_extmark(WalkthroughView.SHOW, math.min(math.max(hunk.top - 1, 0), last - 1), 0, {
          virt_lines = removed,
          virt_lines_above = above,
          priority = WalkthroughView.PRIORITY,
        })
      end
    else
      for row = hunk.top, math.min(hunk.bot, last) do
        buffer:set_extmark(WalkthroughView.SHOW, row - 1, 0, {
          line_hl_group = vgit.BACKGROUND_HL.add,
          number_hl_group = vgit.NUMBER_HL.add,
          priority = WalkthroughView.PRIORITY - 1,
        })
      end

      if #removed > 0 then
        buffer:set_extmark(WalkthroughView.SHOW, math.max(hunk.top - 1, 0), 0, {
          virt_lines = removed,
          virt_lines_above = true,
          priority = WalkthroughView.PRIORITY,
        })
      end
    end
  end

  self.shown[buffer.bufnr] = true

  return hunks
end

function WalkthroughView:_close_split()
  if self.split and self.split:is_valid() then
    self.split:diff_off()
    self.split:close()
  end

  if self.window and self.window:is_valid() and self.diffing then self.window:diff_off() end

  self.split, self.diffing = nil, false
end

function WalkthroughView:_show_split(window, path)
  local base = self:_base_buffer(path)

  if self.split and self.split:is_valid() then
    if self.split:get_buffer().bufnr ~= base.bufnr then
      self.split:diff_off()
      window:diff_off()
      self.split:set_buffer(base)
    end
  else
    self.split = window:split_left(base)
    self.split:set_width(math.floor((self.split:get_width() + window:get_width()) / 2))
    window:focus()
  end

  self.split:diff_this()
  window:diff_this()
  self.diffing = true
end

function WalkthroughView:_diff(window, buffer, path)
  if not self:_base_lines(path) then return false end

  if self:_layout(window) == WalkthroughView.LAYOUT.split then
    self:_show_split(window, path)

    return true
  end

  if self.split then self:_close_split() end

  self:_draw_diff(buffer, window, path)

  return true
end

function WalkthroughView:_keys()
  local keys = settings.keymaps:get('walkthrough')

  return {
    { keys.next, 'next', 'Next step of the walkthrough' },
    { keys.previous, 'previous', 'Previous step of the walkthrough' },
    { keys.next_range, 'next_range', 'Next range of the walkthrough' },
    { keys.previous_range, 'previous_range', 'Previous range of the walkthrough' },
    { keys.overview, 'overview', 'The walkthrough\'s overview' },
    { keys.understood, 'toggle_understood', 'Mark this step understood, or not' },
    { keys.stop, 'stop', 'End the walkthrough' },
    { keys.ask, 'ask', 'Ask about this step' },
    { keys.scroll_down, 'scroll_down', 'Scroll the walkthrough note down', true },
    { keys.scroll_up, 'scroll_up', 'Scroll the walkthrough note up', true },
  }
end

function WalkthroughView:_scroll_keys()
  return vim.tbl_filter(function(key)
    return key[4] == true
  end, self:_keys())
end

function WalkthroughView:_set_keys(buffer, keys)
  for _, key in ipairs(keys) do
    buffer:set_keymap({ key = key[1], mode = 'n', desc = key[3] }, function()
      self[key[2]](self, keymap.count())
    end)
  end
end

function WalkthroughView:_bind(buffer)
  if self.bound[buffer.bufnr] then return end

  self.bound[buffer.bufnr] = true

  self.group.on({ 'BufDelete', 'BufWipeout' }, function()
    Timer.defer(0, function()
      if not self.stopped and self:is_open() then self:stop() end
    end)
  end, { buffer = buffer })

  self:_set_keys(buffer, self:_keys())
end

function WalkthroughView:_bind_scroll()
  local window = self.source and Window(self.source)

  if not (window and window:is_valid()) then return end

  local buffer = window:get_buffer()

  if self.bound[buffer.bufnr] or self.scroll_bound[buffer.bufnr] then return end

  self.scroll_bound[buffer.bufnr] = true
  self:_set_keys(buffer, self:_scroll_keys())
end

function WalkthroughView:_unbind()
  for bufnr in pairs(self.scroll_bound) do
    if Buffer.exists(bufnr) then
      for _, key in ipairs(self:_scroll_keys()) do
        Buffer(bufnr):del_keymap({ key = key[1], mode = 'n' })
      end
    end
  end

  self.scroll_bound = {}

  for bufnr in pairs(self.bound) do
    if Buffer.exists(bufnr) then
      for _, key in ipairs(self:_keys()) do
        Buffer(bufnr):del_keymap({ key = key[1], mode = 'n' })
      end
    end
  end

  self.bound = {}
end

function WalkthroughView:_note_lines(index, part)
  local step = self.walkthrough.steps[index]
  local lines = {}

  if index == 1 and part == 1 and self.walkthrough.summary then
    vim.list_extend(lines, vim.split(self.walkthrough.summary, '\n', { plain = true }))
    vim.list_extend(lines, { '', '---', '' })
  end

  local note = step.note

  if note == '' and self.write_note then
    note = self.note_errors[step] and ('_Could not write a note: ' .. self.note_errors[step] .. '_')
      or WalkthroughView.WRITING
  end

  vim.list_extend(lines, vim.split(note ~= '' and note or (step.title or ''), '\n', { plain = true }))

  return lines
end

function WalkthroughView:_title(index, part)
  local step = self.walkthrough.steps[index]
  local count = #WalkthroughView.ranges(step)

  return string.format(
    ' %d/%d%s%s%s ',
    index,
    #self.walkthrough.steps,
    step.title and (' · ' .. step.title) or '',
    count > 1 and string.format(' · %d/%d', part, count) or '',
    (step.supporting and ' · supporting' or '') .. (step.understood and ' · ✓ understood' or '')
  )
end

function WalkthroughView:_footer(index, part)
  local keys = settings.keymaps:get('walkthrough')
  local count = index and #WalkthroughView.ranges(self.walkthrough.steps[index]) or 0
  local parts = {}

  if index and (index > 1 or (part or 1) > 1) then parts[#parts + 1] = keys.previous .. ' back' end

  parts[#parts + 1] = keys.next .. ((index or 0) >= #self.walkthrough.steps and ' finish' or ' next')

  if count > 1 then parts[#parts + 1] = keys.next_range .. '/' .. keys.previous_range .. ' range' end

  parts[#parts + 1] = keys.overview .. ' overview'

  if index then
    parts[#parts + 1] = keys.ask .. ' ask'
    parts[#parts + 1] = keys.understood .. (self.walkthrough.steps[index].understood and ' not yet' or ' got it')
  end

  parts[#parts + 1] = keys.scroll_down .. '/' .. keys.scroll_up .. ' scroll'
  parts[#parts + 1] = keys.stop .. ' end'

  return ' ' .. table.concat(parts, ' · ') .. ' '
end

function WalkthroughView:_close_note()
  if self.note and self.note:is_valid() then self.note:close() end

  self.note, self.note_buffer = nil, nil
end

function WalkthroughView:_show_note(window, first, lines, title, footer)
  self:_close_note()

  local spec = settings.walkthrough
  local width = math.max(math.floor(window:get_width() * spec:get('note_width')), spec:get('note_min_width'))
  local top, bottom = window:get_visible_range()
  local lower = (first + 1 - top) / math.max(bottom - top, 1) > 0.5
  local buffer = Buffer():create(false, true)

  width = math.min(width, math.max(window:get_width() - 2, 10))
  buffer:set_lines(lines)
  buffer:set_option('filetype', Panel.MARKDOWN)
  buffer:set_option('bufhidden', 'wipe')
  Renderer(buffer.bufnr):render(0)

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
    title = title,
    title_pos = 'left',
    footer = footer,
    footer_pos = 'right',
  })
  self.note_buffer = buffer
  self.note:assign_options({
    wrap = true,
    linebreak = true,
    conceallevel = 2,
    winhl = 'Normal:UiComposer,FloatBorder:UiMuted,FloatTitle:UiTitle,FloatFooter:UiMuted',
  })

  self.note:set_height(math.max(1, math.min(spec:get('note_height'), window:get_height() - 2)))
end

function WalkthroughView:_scroll_note(rows)
  local note = self.note

  if not (note and note:is_valid()) then return false end

  local last = self.note_buffer:get_line_count()
  local top = note:get_view().topline

  if rows > 0 and note:get_text_height(top, last) <= note:get_height() then return false end
  if rows < 0 and top <= 1 then return false end

  if rows > 0 then
    note:scroll_down(rows)
  else
    note:scroll_up(-rows)
  end

  return true
end

function WalkthroughView:scroll_down()
  return self:_scroll_note(settings.walkthrough:get('note_scroll'))
end

function WalkthroughView:scroll_up()
  return self:_scroll_note(-settings.walkthrough:get('note_scroll'))
end

function WalkthroughView:_present(path, place)
  local buffer = self:_buffer(path)
  local window = self:_code_window() or self:_open_beside(buffer)

  if not window then return nil, 'no window to show the code in' end

  self:_clear()

  if window:get_buffer().bufnr ~= buffer.bufnr then
    if self.diffing then window:diff_off() end

    window:set_buffer(buffer)
  end

  local diffed = self:_diff(window, buffer, path)
  local first, finish = place(buffer)

  self:_mark(buffer, first, finish, self:_label(first, finish), diffed)
  self:_bind(buffer)
  self:_bind_scroll()

  window:set_cursor({ first + 1, 0 })
  window:scroll_to('center')

  self:_watch(window)

  return window, first
end

function WalkthroughView:_watch(window)
  if not (self.window and self.window:is_same(window)) then
    self.group.on('WinClosed', function()
      Timer.defer(0, function()
        if not self.stopped and self:is_open() then self:stop() end
      end)
    end, { pattern = tostring(window.win_id), once = true })
  end

  self.window = window
end

function WalkthroughView:_label()
  local step = self.walkthrough.steps[self.pending]

  if not step then return ' not covered ' end

  local count = #WalkthroughView.ranges(step)

  return string.format(
    ' %d/%d%s%s%s ',
    self.pending,
    #self.walkthrough.steps,
    step.title and (' · ' .. step.title) or '',
    count > 1 and string.format(' · %d/%d', self.pending_part, count) or '',
    self.walkthrough.rev and (' @' .. self.walkthrough.rev:sub(1, 7)) or ''
  )
end

function WalkthroughView:show(index, part)
  local step = self.walkthrough.steps[index]

  if not step then return false end

  local ranges = WalkthroughView.ranges(step)

  part = math.min(math.max(part or 1, 1), #ranges)

  self.pending, self.pending_part = index, part

  local window, first = self:_present(ranges[part].path, function(buffer)
    local from, to = self:_range(index, part, buffer)

    self:_track(index, part, buffer, from, to)

    return from, to
  end)

  if not window then return false, first end

  self.index, self.part = index, part
  self.seen[index] = true
  self.visiting = nil
  self.started, self.overviewing = true, false

  self.note_first = first
  self:_show_note(window, first, self:_note_lines(index, part), self:_title(index, part), self:_footer(index, part))
  self:_write_notes(index)

  return true
end

function WalkthroughView:_write_notes(index)
  if not self.write_note then return end

  local step = self.walkthrough.steps[index]

  if step.note == '' and not self.note_errors[step] then
    self.write_note(index, function(_, err)
      if err then self.note_errors[step] = err end

      self:_refresh_note(step)
    end)
  end

  local following = self.walkthrough.steps[index + 1]

  if following and following.note == '' then self.write_note(index + 1) end
end

function WalkthroughView:_refresh_note(step)
  if self.stopped or self.overviewing or self.visiting then return end
  if self.walkthrough.steps[self.index] ~= step then return end
  if not (self.window and self.window:is_valid()) then return end

  self:_show_note(
    self.window,
    self.note_first,
    self:_note_lines(self.index, self.part),
    self:_title(self.index, self.part),
    self:_footer(self.index, self.part)
  )
end

function WalkthroughView:visit(hunk)
  if not self:is_open() then return false end

  self.pending = nil

  local window, first = self:_present(hunk.absolute, function(buffer)
    local last = buffer:get_line_count() - 1
    local from = math.min(math.max(hunk.first - 1, 0), last)

    return from, math.min(math.max(hunk.last - 1, from), last)
  end)

  if not window then return false, first end

  self.visiting = hunk

  local path = fs.make_relative(self.walkthrough.root or fs.cwd(), hunk.absolute)

  self:_show_note(
    window,
    first,
    { string.format('No step covers `%s:%d-%d`.', path, hunk.first, hunk.last) },
    ' not covered ',
    self:_footer(nil)
  )

  return true
end

function WalkthroughView:_overview_buffer()
  local buffer = self.snapshots.overview

  if buffer and buffer:is_valid() then return buffer end

  buffer = Buffer():create(false, true)
  buffer:set_name(string.format('walkthrough://%d/%s', self.id, self.walkthrough.title))
  buffer:set_option('filetype', Panel.MARKDOWN)
  buffer:set_option('bufhidden', 'hide')
  buffer:set_option('modifiable', false)
  buffer:set_keymap({ key = settings.keymaps:get('walkthrough').open, mode = 'n', desc = 'Open this step' }, function()
    self:open_row()
  end)

  self.snapshots.overview = buffer

  return buffer
end

function WalkthroughView:overview()
  if self.stopped then return false end

  local keys = settings.keymaps:get('walkthrough')
  local view = walkthrough_overview.render(self.walkthrough, { index = self.index, seen = self.seen, keys = keys })
  local buffer = self:_overview_buffer()
  local window = self:_code_window() or self:_open_beside(buffer)

  if not window then return false, 'no window to show the walkthrough in' end

  self:_clear()
  self:_close_note()
  self:_close_split()

  buffer:set_lines(view.lines)
  Renderer(buffer.bufnr):render(0)

  if window:get_buffer().bufnr ~= buffer.bufnr then window:set_buffer(buffer) end

  self:_bind(buffer)
  self:_watch(window)

  local current
  for row, target in pairs(view.targets) do
    if target.index == self.index then current = row end
  end

  window:set_cursor({ current or walkthrough_overview.first_target(view) or 1, 0 })

  self.targets = view.targets
  self.started, self.overviewing, self.visiting = true, true, nil

  return true
end

function WalkthroughView:open_row()
  if not (self.overviewing and self.window and self.window:is_valid()) then return false end

  local target = self.targets[self.window:get_cursor()[1]]

  if not target then return false end
  if target.hunk then return self:visit(target.hunk) end

  return self:show(target.index)
end

function WalkthroughView:ask()
  if self.on_ask then self.on_ask(self) end
end

function WalkthroughView:step()
  return self.walkthrough.steps[self.index], self.index, self.part
end

function WalkthroughView:_step_for(path)
  if type(path) ~= 'string' or path == '' then return nil end

  local root = self.walkthrough.root
  local relative

  if root and path:sub(1, 6) == 'rev://' then relative = path:match('^rev://[^/]+/(.+)$') end

  local found, found_part

  for index, step in ipairs(self.walkthrough.steps) do
    for part, range in ipairs(WalkthroughView.ranges(step)) do
      local matches = relative and fs.make_relative(root, range.path) == relative
        or (not relative and fs.normalize(range.path) == fs.normalize(path))

      if matches then
        if index == self.index then return index, part end

        found, found_part = found or index, found_part or part
      end
    end
  end

  return found, found_part
end

function WalkthroughView:select(path, first, last)
  if not self:is_open() then return false end

  local index, part = self:_step_for(path)

  if not index then return false end

  local step = self.walkthrough.steps[index]
  local range = WalkthroughView.ranges(step)[part]

  range.line = math.max(math.floor(first or range.line), 1)
  range.end_line = math.max(math.floor(last or range.line), range.line)

  if part == 1 then
    step.line, step.end_line = range.line, range.end_line
  end

  self:_forget(index)

  return self:show(index, part)
end

function WalkthroughView:_forget(from)
  for index = #self.walkthrough.steps, from, -1 do
    for _, anchor in pairs(self.anchors[index] or {}) do
      if Buffer.exists(anchor.bufnr) then Buffer(anchor.bufnr):del_extmark(WalkthroughView.TRACK, anchor.id) end
    end

    self.anchors[index] = nil
  end
end

function WalkthroughView:_shift(from, count)
  for index = #self.walkthrough.steps, from, -1 do
    self.anchors[index + count], self.anchors[index] = self.anchors[index], nil

    if self.seen[index] then
      self.seen[index + count], self.seen[index] = true, nil
    end
  end
end

function WalkthroughView:insert(steps)
  local at = self.index

  self:_shift(at + 1, #steps)

  for offset, step in ipairs(steps) do
    table.insert(self.walkthrough.steps, at + offset, step)
  end

  return self:show(at + 1)
end

function WalkthroughView:replace_rest(steps)
  self:_forget(self.index + 1)

  for index = #self.walkthrough.steps, self.index + 1, -1 do
    table.remove(self.walkthrough.steps, index)
    self.seen[index] = nil
  end

  vim.list_extend(self.walkthrough.steps, steps)

  return self:show(math.min(self.index + 1, #self.walkthrough.steps))
end

function WalkthroughView:toggle_understood()
  local step = self.walkthrough.steps[self.index]

  if self.index == 0 or not step or self.overviewing or self.visiting then return false end

  step.understood = not step.understood

  self:_refresh_note(step)

  return true
end

function WalkthroughView:add_to_note(step, text)
  step.note = step.note ~= '' and (step.note .. '\n\n---\n\n' .. text) or text

  self:_refresh_note(step)

  return true
end

function WalkthroughView:annotate(note)
  if self.index == 0 then return false, 'no step is open' end

  self.walkthrough.steps[self.index].note = note

  return self:show(self.index, self.part)
end

WalkthroughView.MODE = { insert = 'insert', replace = 'replace', note = 'note' }

function WalkthroughView:apply(update)
  if not self:is_open() then return false, 'the walkthrough is not showing' end

  if update.mode == WalkthroughView.MODE.note then return self:annotate(update.note or '') end
  if update.mode == WalkthroughView.MODE.replace then return self:replace_rest(update.steps or {}) end

  return self:insert(update.steps or {})
end

function WalkthroughView:start(index)
  local ok, why = self:show(index or 1)

  if ok then self.window:focus() end

  return ok, why
end

function WalkthroughView:start_overview()
  local ok, why = self:overview()

  if ok then
    self.window:focus()

    if self.write_note and #self.walkthrough.steps > 0 and self.walkthrough.steps[1].note == '' then
      self.write_note(1)
    end
  end

  return ok, why
end

function WalkthroughView:_resume_step()
  return self:show(math.max(self.index, 1), self.index > 0 and self.part or 1)
end

function WalkthroughView:next(count)
  if self.visiting or self.overviewing then return self:_resume_step() end
  if self.index >= #self.walkthrough.steps then return self:stop() end

  return self:show(math.min(self.index + math.max(count or 1, 1), #self.walkthrough.steps))
end

function WalkthroughView:previous(count)
  if self.visiting or self.overviewing then return self:_resume_step() end

  return self:show(math.max(self.index - math.max(count or 1, 1), 1))
end

function WalkthroughView:next_range(count)
  if self.index == 0 then return self:_resume_step() end

  local index, part = self.index, self.part

  for _ = 1, math.max(count or 1, 1) do
    if part < #WalkthroughView.ranges(self.walkthrough.steps[index]) then
      part = part + 1
    elseif index < #self.walkthrough.steps then
      index, part = index + 1, 1
    end
  end

  if index == self.index and part == self.part and not self.visiting then return false end

  return self:show(index, part)
end

function WalkthroughView:previous_range(count)
  if self.index == 0 then return self:_resume_step() end

  local index, part = self.index, self.part

  for _ = 1, math.max(count or 1, 1) do
    if part > 1 then
      part = part - 1
    elseif index > 1 then
      index = index - 1
      part = #WalkthroughView.ranges(self.walkthrough.steps[index])
    end
  end

  if index == self.index and part == self.part and not self.visiting then return false end

  return self:show(index, part)
end

function WalkthroughView:stop()
  if self.stopped then return false end

  self.stopped = true
  self.last_index = self.index

  self:_clear()
  self:_close_note()
  self:_close_split()
  self:_unbind()

  self:_forget(1)

  for _, snapshot in pairs(self.snapshots) do
    if snapshot:is_valid() then snapshot:delete() end
  end

  self.snapshots, self.bases, self.anchors, self.index = {}, {}, {}, 0

  if self.group then self.group.dispose() end

  if self.on_stop then self.on_stop(self) end

  return true
end

return WalkthroughView

local lazy = require('core.lazy')

local text = lazy('core.text')
local glitch = lazy('ui.glitch')
local Timer = lazy('core.Timer')
local design = lazy('ui.design')
local theme = lazy('sn.transcript.theme')
local format = require('sn.picker.format')
local indicators = lazy('ui.pixel.indicators')

local TUNE_STATIC = 'medium'
local SECTION = format.SECTION
local shorten = format.shorten

local list = {}

function list:_tuning()
  local tune = self._tune

  if not tune or theme.reduced() then return nil end

  local progress = (Timer.now() - tune.started) / design.motion.DURATION.moderate

  if progress >= 1 then return nil end

  return tune, progress
end

function list:_stop_tuner()
  if self._tuner then self._tuner:close() end

  self._tuner = nil
end

function list:_start_tune()
  if theme.reduced() then return end

  self._tune = { started = Timer.now() }
  self:_stop_tuner()
  self._tuner = Timer()
  self._tuner:every(design.static.FRAME_MS, function()
    if not self:is_open() or not self:_tuning() then
      self:_stop_tuner()
      self._tune = nil
    end

    if self:is_open() then self:_draw_list() end
  end)
end

local function match_ranges(positions, limit)
  local ranges, from, last = {}, nil, nil

  for _, at in ipairs(positions or {}) do
    if at <= limit then
      if from and at == last + 1 then
        last = at
      else
        if from then ranges[#ranges + 1] = { from, last } end

        from, last = at, at
      end
    end
  end

  if from then ranges[#ranges + 1] = { from, last } end

  return ranges
end

function list:_snow(width)
  local seed = math.floor(Timer.now() / 120)
  local rows = {}

  for i = 1, 3 do
    rows[i] = glitch.snow(math.max(8, width - 6), seed, i)
  end

  return rows
end

function list:_draw_list()
  local body = self._body

  if not body or not body.elements.list or self._loading then return end

  local list = body.elements.list

  if not list:is_valid() then return end

  local window = list:get_window()
  local width = window and window:get_width() or 70
  local inner = math.max(24, width - 2)
  local rows = self._filtered
  local lines, highlights, overlays = {}, {}, {}
  local line_of, row_of = {}, {}
  local tune, progress = self:_tuning()
  local sectioned = self._query == '' and self._mode == 'sessions'
  local section

  local function push(line)
    lines[#lines + 1] = line

    return #lines - 1
  end

  for i, row in ipairs(rows) do
    if sectioned and row.section and row.section ~= section then
      local count = 0

      for _, other in ipairs(rows) do
        if other.section == row.section then count = count + 1 end
      end

      local at = push(' ' .. SECTION[row.section] .. ' ' .. count)

      highlights[#highlights + 1] = { hl = 'UiMuted', row = at, col_range = { from = 1, to = #lines[#lines] } }
    end

    section = row.section or section

    local loading = self._loading and row.stored and row.stored.id == self._loading.id
    local meta = shorten(loading and 'loading' or row.meta or '', math.max(8, math.floor(inner / 2)))
    local label = shorten(row.label or '', math.max(8, inner - text.width(meta) - 4))
    local icon = row.icon or ' '

    if loading then label = glitch.scramble(label, design.static.density('light'), design.static.seed(Timer.now())) end
    local head = ' ' .. icon .. ' ' .. label
    local tail = meta ~= '' and (' ' .. meta .. ' ') or ''
    local gap = tail ~= '' and string.rep(' ', math.max(1, width - text.width(head) - text.width(tail))) or ''
    local at = push(head .. gap .. tail)
    local line = lines[#lines]
    local origin = 2 + #icon

    line_of[i], row_of[at + 1] = at + 1, i

    highlights[#highlights + 1] = { hl = row.icon_hl or 'UiMuted', row = at, col_range = { from = 1, to = 1 + #icon } }

    if row.label_hl then
      highlights[#highlights + 1] = { hl = row.label_hl, row = at, col_range = { from = origin, to = #head } }
    end

    for _, range in ipairs(match_ranges(row.match, #label)) do
      highlights[#highlights + 1] =
        { hl = 'UiAccent', row = at, col_range = { from = origin + range[1] - 1, to = origin + range[2] } }
    end

    if tail ~= '' then
      highlights[#highlights + 1] = { hl = 'UiMuted', row = at, col_range = { from = #head + #gap, to = #line } }
    end

    local indicator = row.indicator and indicators.chunk(row.indicator[1], row.indicator[2])

    if loading then indicator = indicators.chunk('loading', 'accent') end

    if indicator then overlays[#overlays + 1] = { texts = { indicator }, row = at, col = 1, pos = 'overlay' } end

    if tune and i == self._selected then
      local seed = design.static.seed(Timer.now())

      for _, cell in ipairs(glitch.cols(label, design.static.density(TUNE_STATIC, 1 - progress), seed)) do
        overlays[#overlays + 1] =
          { texts = { { cell[2], 'UiMuted' } }, row = at, col = origin + cell[1], pos = 'overlay' }
      end
    end
  end

  if #rows == 0 then
    local at = push('  no matches')

    highlights[#highlights + 1] = { hl = 'UiMuted', row = at, col_range = { from = 2, to = #lines[#lines] } }

    if not theme.reduced() then
      for _, snow in ipairs(self:_snow(width)) do
        local row = push('  ' .. snow)

        highlights[#highlights + 1] = { hl = 'UiMuted', row = row, col_range = { from = 2, to = #lines[#lines] } }
      end
    end
  end

  local signature = {}

  for _, mark in ipairs(highlights) do
    signature[#signature + 1] = mark.hl .. mark.row .. ':' .. mark.col_range.from .. '-' .. mark.col_range.to
  end

  for _, mark in ipairs(overlays) do
    signature[#signature + 1] = 'o' .. mark.row .. ':' .. mark.col .. vim.inspect(mark.texts)
  end

  local key = table.concat(lines, '\n') .. '\0' .. table.concat(signature, ';')

  self._rows_at, self._line_of = row_of, line_of

  if key ~= self._drawn then
    self._drawn = key

    list:set_lines(lines)
    list:clear_extmark_highlights()
    list:clear_extmark_texts()

    for _, mark in ipairs(highlights) do
      list:place_extmark_highlight(mark)
    end

    for _, mark in ipairs(overlays) do
      list:place_extmark_text(mark)
    end
  end

  body._drawing = true
  list:set_cursor({ math.min(line_of[self._selected] or 1, #lines), 0 })
  body._drawing = false
end

return list

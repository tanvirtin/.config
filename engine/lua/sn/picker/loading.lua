local lazy = require('core.lazy')

local glitch = lazy('ui.glitch')
local Timer = lazy('core.Timer')
local motion = lazy('ui.motion')
local design = lazy('ui.design')
local client = lazy('sn.client')
local Buffer = lazy('core.editor.Buffer')
local theme = lazy('sn.transcript.theme')
local format = require('sn.picker.format')

local shorten = format.shorten
local STATIC, STATIC_BAND = 'whisper', 'medium'
local LISTING_MAX_MS = 5000
local GLITCH = Buffer.namespace('sn.session_picker.glitch')

local loading = {}

function loading:_listed()
  if self._listing then
    self._listing.pending = math.max(0, self._listing.pending - 1)

    if self._listing.pending == 0 and Timer.now() >= self._listing.ends_at then return self:_end_listing() end
  end

  self:refresh()
end

function loading:_begin_listing()
  if self._mode ~= 'sessions' or theme.reduced() then return end

  local names = client.agents()

  if #names == 0 then return end

  self._listing = {
    pending = #names,
    ends_at = Timer.now() + design.motion.DURATION.moderate,
    gives_up = Timer.now() + LISTING_MAX_MS,
  }
  self._lister = Timer()
  self._lister:every(motion.STEP_MS, function()
    if not self:is_open() or not self._listing then return self:_stop_lister() end
    if self._listing.pending == 0 and Timer.now() >= self._listing.ends_at then return self:_end_listing() end
    if Timer.now() >= self._listing.gives_up then return self:_end_listing() end

    self:_draw_static_state()
  end)
end

function loading:_stop_lister()
  if self._lister then self._lister:close() end

  self._lister = nil
end

function loading:_cancel_listing()
  self._listing = nil
  self:_stop_lister()
  self:_clear_static()
  self._drawn, self._detail_drawn = nil, nil
end

function loading:_end_listing()
  self:_cancel_listing()

  if self:is_open() then self:refresh() end
end

function loading:_begin_loading(entry)
  if self._loading then return false end

  self._loading = { id = entry.id, title = entry.title or 'untitled', started = Timer.now() }
  self._drawn, self._detail_drawn = nil, nil
  self:_stop_tuner()
  self._loader = Timer()
  self._loader:every(motion.STEP_MS, function()
    if not self:is_open() or not self._loading then return self:_stop_loader() end

    self:_draw_static_state()
  end)

  self:_draw_static_state()

  return true
end

function loading:_stop_loader()
  if self._loader then self._loader:close() end

  self._loader = nil
end

function loading:_end_loading()
  self._loading = nil
  self:_stop_loader()
  self:_clear_static()
  self._drawn, self._detail_drawn = nil, nil

  if self:is_open() then self:refresh() end
end

function loading:_draw_static_state()
  local body = self._body

  if not body or not self:is_open() or not (self._loading or self._listing) then return end

  local seed = motion.step(Timer.now())
  local top = body.elements.title:get_window():get_position()[1]
  local band = seed * 2 % math.max(1, self:height())

  if self._loading then self:_draw_static_title(seed, 'loading', self._loading.title or 'untitled') end

  for _, pane in ipairs({ 'list', 'detail' }) do
    self:_draw_static(body.elements[pane], seed, band, top)
  end
end

function loading:_clear_static()
  local body = self._body

  if not body then return end

  for _, pane in ipairs({ 'list', 'detail' }) do
    local element = body.elements[pane]

    if element and element:is_valid() then element:get_buffer():clear_namespace(GLITCH, 0, -1) end
  end
end

function loading:_draw_static_title(seed, label, name)
  local title = self._body.elements.title

  if not title:is_valid() then return end

  local prefix = ' ' .. label .. string.rep('.', seed % 4) .. ' '
  local line = prefix .. shorten(name, self:width() - #prefix - 2)

  title:set_lines({ line })
  title:clear_extmark_highlights()
  title:clear_extmark_texts()
  title:place_extmark_highlight({ hl = 'UiAccent', row = 0, col_range = { from = 1, to = #prefix - 1 } })
  title:place_extmark_highlight({ hl = 'UiTitle', row = 0, col_range = { from = #prefix, to = #line } })
end

function loading:_draw_static(element, seed, band, top)
  if not element or not element:is_valid() then return end

  local buffer = element:get_buffer()

  buffer:clear_namespace(GLITCH, 0, -1)

  if theme.reduced() then return end

  local window = element:get_window()
  local offset = window:get_position()[1] - top
  local first, last = window:get_visible_range()
  local lines = buffer:get_lines(first, math.min(last, element:get_line_count()))

  for offset_row, line in ipairs(lines) do
    local index = first + offset_row
    local from = #(line:match('^[%s>]*') or '')
    local dense = math.abs(offset + index - 1 - band) <= 1
    local density = design.static.density(dense and STATIC_BAND or STATIC)

    for _, cell in ipairs(glitch.cols(line, density, seed + index, from)) do
      buffer:set_extmark(GLITCH, index - 1, cell[1], {
        virt_text = { { cell[2], dense and 'UiThought' or 'UiThoughtFade2' } },
        virt_text_pos = 'overlay',
        priority = design.layer.of('effect'),
      })
    end
  end
end

return loading

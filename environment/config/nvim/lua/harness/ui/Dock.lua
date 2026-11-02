local lazy = require('core.lazy')

local Buffer = lazy('core.Buffer')
local Object = lazy('core.Object')
local Window = lazy('core.Window')
local settings = lazy('harness.settings')

local Dock = Object:extend()

Dock.PRESET = { compact = 'compact', half = 'half', zoom = 'zoom' }

Dock.PREFIX = 'harness://'

function Dock:constructor(tab)
  return {
    tab = tab,
    window = nil,
    view = nil,
    width = nil,
    preset = nil,
    zoom = nil,
  }
end

function Dock:is_open()
  return self.window ~= nil and self.window:is_valid()
end

function Dock:is_zoomed()
  return self.zoom ~= nil and self.zoom:is_valid()
end

function Dock:preset_width(preset)
  local spec = settings.transcript
  local fraction = preset == Dock.PRESET.half and spec:get('half_width') or spec:get('tile_width')

  return math.max(spec:get('tile_min_width'), math.floor(Window.screen_width() * fraction))
end

function Dock:_fix(window)
  window:set_option('winfixwidth', true)
  window:set_option('winfixbuf', true)

  return self
end

function Dock:_put(window, view)
  window:set_option('winfixbuf', false)
  view:show_in(window)
  self.view = view

  return self:_fix(window)
end

function Dock:_vacate(view)
  for _, window in ipairs(view:windows()) do
    if window:get_tab() == self.tab and window.win_id ~= self.window.win_id then
      if view.source_buf and Buffer.exists(view.source_buf) then
        window:set_buffer(Buffer(view.source_buf))
      else
        window:close()
      end
    end
  end

  return self
end

function Dock:open(view, preset)
  if self:is_open() then return self:show(view) end

  self.preset = preset or self.preset or Dock.PRESET.compact
  self.width = preset and self:preset_width(preset) or self.width or self:preset_width(self.preset)

  self.window = Window.split_far_right(self.width)
  self:_put(self.window, view)
  self.window:set_width(self.width)
  self:_vacate(view)

  return self
end

function Dock:show(view)
  if not self:is_open() then return self:open(view) end

  return self:_put(self.window, view)
end

function Dock:resize(preset)
  self.preset = preset
  self.width = self:preset_width(preset)

  if self:is_open() then self.window:set_width(self.width) end

  return self
end

function Dock:observe()
  if self:is_open() then self.width = self.window:get_width() end

  return self
end

function Dock:focus()
  if self:is_open() then self.window:focus() end

  return self
end

function Dock:close()
  if self:is_open() then self.window:close() end

  self.window = nil

  return self
end

function Dock:_code(window)
  if not window:is_valid() or window:get_tab() ~= self.tab then return false end
  if window:get_config().relative ~= '' then return false end

  return window:get_buffer():get_name():sub(1, #Dock.PREFIX) ~= Dock.PREFIX
end

function Dock:center()
  local candidates = { Window.previous() }

  vim.list_extend(candidates, Window.in_tab(self.tab))

  for _, window in ipairs(candidates) do
    if self:_code(window) then return window end
  end

  return Window.split_far_left()
end

function Dock:zoom_in()
  local view = self.view

  if self:is_zoomed() or not view then return self end

  local alone = #Window.in_tab(self.tab) <= 1

  self.zoom = Window.tab_with(view.buffer)
  self.zoom:set_option('winfixbuf', true)

  if self:is_open() and not alone then self:close() end

  self.preset = Dock.PRESET.zoom

  return self
end

function Dock:zoom_out()
  local zoom = self.zoom

  self.zoom = nil

  if not zoom then return self end

  if Window.tab_valid(self.tab) then
    Window.go_to_tab(self.tab)

    if self.view and not self:is_open() then self:open(self.view, Dock.PRESET.compact) end

    self.preset = Dock.PRESET.compact
  end

  if zoom:is_valid() then zoom:close() end

  return self
end

return Dock

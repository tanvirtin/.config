local Buffer = require('core.Buffer')
local Window = require('core.Window')
local markup = require('ui.markup')

local Float = {}

Float.__index = Float

Float.ZINDEX = 200

function Float.new(opts)
  local buffer = Buffer():create(false, true)

  buffer:set_option('bufhidden', 'wipe')

  local instance = setmetatable({
    buffer = buffer,
    width = math.max(1, opts.width or 1),
    height = math.max(1, opts.height or 1),
    x = opts.x or 0,
    y = opts.y or 0,
    key = nil,
    hidden = false,
  }, Float)

  instance.window = Window.get_current():open(buffer, {
    relative = 'editor',
    row = instance.y,
    col = instance.x,
    width = instance.width,
    height = instance.height,
    style = 'minimal',
    border = opts.border,
    focusable = false,
    zindex = opts.z or Float.ZINDEX,
    noautocmd = true,
  })
  instance.window:set_option('winhl', 'Normal:' .. (opts.normal or 'NormalFloat'))
  instance.window:set_option('winblend', opts.blend or 0)

  return instance
end

function Float:is_valid()
  return self.window ~= nil and self.window:is_valid()
end

function Float:set_content(lines, tick)
  local key = table.concat(lines, '\n') .. '\0' .. tostring(tick)

  if key == self.key or not self:is_valid() then return self end

  self.key = key

  local shown, highlights = markup.render(lines, tick)

  self.buffer:set_lines(shown)
  self.buffer:clear_extmark_highlights()

  for _, mark in ipairs(highlights) do
    self.buffer:place_extmark_highlight({ hl = mark.hl, row = mark.row, col_range = { from = mark.from, to = mark.to } })
  end

  return self
end

function Float:resize(width, height)
  width, height = math.max(1, width), math.max(1, height)

  if width == self.width and height == self.height then return self end

  self.width, self.height = width, height

  return self:_config({ width = width, height = height })
end

function Float:_config(config)
  if not self:is_valid() then return self end

  local current = self.window:get_config()

  pcall(self.window.set_config, self.window, {
    relative = 'editor',
    row = self.y,
    col = self.x,
    width = self.width,
    height = self.height,
    zindex = current.zindex,
    hide = self.hidden,
    focusable = false,
    style = 'minimal',
    border = current.border,
    noautocmd = true,
  })

  return self
end

function Float:place(x, y, hidden)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)

  if x == self.x and y == self.y and hidden == self.hidden then return self end

  self.x, self.y, self.hidden = x, y, hidden

  return self:_config()
end

function Float:move(x, y)
  return self:place(x, y, self.hidden)
end

function Float:set_blend(blend)
  if self:is_valid() then self.window:set_option('winblend', math.max(0, math.min(100, math.floor(blend + 0.5)))) end

  return self
end

function Float:set_hidden(hidden)
  return self:place(self.x, self.y, hidden)
end

function Float:close()
  if self.window and self.window:is_valid() then self.window:close() end
  if self.buffer:is_valid() then self.buffer:delete({ force = true }) end

  self.window = nil

  return self
end

return Float

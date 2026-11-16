local Track = require('ui.anim.Track')

local Shape = {}

Shape.__index = Shape

Shape.KINDS = { 'circle', 'glow', 'ring', 'rect', 'line' }
Shape.FIELDS = { 'r', 'w', 'h', 'x2', 'y2', 'opacity', 'thick' }
Shape.DEFAULTS = { r = 1, w = 4, h = 2, opacity = 100, thick = 2 }

local DRAW = {}

function DRAW.circle(self, bitmap, v, x, y, rgb, alpha)
  bitmap:disc(x, y, v.r * self.cell[2], rgb, alpha)
end

function DRAW.glow(self, bitmap, v, x, y, rgb, alpha)
  bitmap:glow(x, y, v.r * self.cell[2], rgb, alpha)
end

function DRAW.ring(self, bitmap, v, x, y, rgb, alpha)
  bitmap:ring(x, y, v.r * self.cell[2], v.thick, rgb, alpha)
end

function DRAW.rect(self, bitmap, v, x, y, rgb, alpha)
  local width, height = v.w * self.cell[1], v.h * self.cell[2]

  if self.anchor == 'center' then
    x, y = x - width / 2, y - height / 2
  end

  bitmap:rect(x, y, width, height, rgb, alpha, self.round)
end

function DRAW.line(self, bitmap, v, x, y, rgb, alpha)
  local x2, y2 = self.layer:point(v.x2 or 0, v.y2 or 0)

  bitmap:line(x, y, x2, y2, v.thick, rgb, alpha)
end

function Shape.new(spec, tracks, layer)
  if not DRAW[spec.shape] then
    error(string.format('unknown shape %s (%s)', tostring(spec.shape), table.concat(Shape.KINDS, ', ')), 0)
  end

  local instance = setmetatable({
    kind = spec.shape,
    layer = layer,
    cell = layer.CELL,
    at = spec.at,
    anchor = spec.anchor,
    round = spec.round,
    rgb = layer:color(spec.color or 'accent'),
    from_ms = spec.show_ms or 0,
    until_ms = spec.hide_ms,
    tracks = tracks,
    fixed = {},
  }, Shape)

  for _, field in ipairs(Shape.FIELDS) do
    local value = spec[field]

    if type(value) == 'table' and not tracks[field] then
      tracks[field] = Track.new(value)
    elseif type(value) == 'number' then
      instance.fixed[field] = value
    end
  end

  return instance
end

function Shape:duration()
  local longest = self.until_ms or 0

  for _, track in pairs(self.tracks) do
    longest = math.max(longest, track:duration())
  end

  return longest
end

function Shape:_value(field, ms)
  local track = self.tracks[field]

  if track then return track:at(ms) end

  return self.fixed[field] or Shape.DEFAULTS[field]
end

function Shape:update(ms)
  if ms < self.from_ms or (self.until_ms and ms > self.until_ms) then return end

  local values = {}

  for _, field in ipairs(Shape.FIELDS) do
    values[field] = self:_value(field, ms)
  end

  local alpha = math.max(0, math.min(100, values.opacity)) / 100

  if alpha <= 0 then return end

  local x, y = self.layer:point(self:_value('x', ms) or self.at[1], self:_value('y', ms) or self.at[2])

  DRAW[self.kind](self, self.layer.bitmap, values, x, y, self.rgb, alpha)
end

function Shape:destroy() end

return Shape

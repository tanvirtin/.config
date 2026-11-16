local ffi = require('ffi')

local Bitmap = {}

Bitmap.__index = Bitmap

local floor, ceil, max, min, sqrt, abs = math.floor, math.ceil, math.max, math.min, math.sqrt, math.abs
local sin, cos, atan2, TAU = math.sin, math.cos, math.atan2, 2 * math.pi

function Bitmap.new(width, height)
  return setmetatable({
    width = width,
    height = height,
    data = ffi.new('uint8_t[?]', width * height * 4),
    left = width,
    top = height,
    right = -1,
    bottom = -1,
    clip_left = 0,
    clip_top = 0,
    clip_right = width,
    clip_bottom = height,
  }, Bitmap)
end

function Bitmap.rgb(color)
  return { floor(color / 65536) % 256, floor(color / 256) % 256, color % 256 }
end

function Bitmap:dirty()
  return self.right >= self.left and self.bottom >= self.top
end

function Bitmap:bounds()
  return self.left, self.top, self.right, self.bottom
end

function Bitmap:clear()
  if self:dirty() then
    local span = (self.right - self.left + 1) * 4

    for y = self.top, self.bottom do
      ffi.fill(self.data + (y * self.width + self.left) * 4, span, 0)
    end
  end

  self.left, self.top, self.right, self.bottom = self.width, self.height, -1, -1

  return self:unclip()
end

function Bitmap:clip(x, y, width, height)
  self.clip_left, self.clip_top = max(0, floor(x)), max(0, floor(y))
  self.clip_right, self.clip_bottom = min(self.width, ceil(x + width)), min(self.height, ceil(y + height))

  return self
end

function Bitmap:unclip()
  self.clip_left, self.clip_top, self.clip_right, self.clip_bottom = 0, 0, self.width, self.height

  return self
end

function Bitmap:pixel(x, y)
  local at = (y * self.width + x) * 4
  local data = self.data

  return data[at], data[at + 1], data[at + 2], data[at + 3]
end

function Bitmap:_fill(x0, y0, x1, y1, rgb, alpha, coverage)
  x0, y0 = max(self.clip_left, floor(x0)), max(self.clip_top, floor(y0))
  x1, y1 = min(self.clip_right - 1, ceil(x1)), min(self.clip_bottom - 1, ceil(y1))

  if x1 < x0 or y1 < y0 or alpha <= 0 then return self end

  local data, width = self.data, self.width
  local r, g, b = rgb[1], rgb[2], rgb[3]

  for y = y0, y1 do
    for x = x0, x1 do
      local source = alpha * coverage(x + 0.5, y + 0.5)

      if source > 0 then
        local at = (y * width + x) * 4
        local under = data[at + 3] / 255 * (1 - min(source, 1))
        local out = min(source, 1) + under

        data[at] = (r * min(source, 1) + data[at] * under) / out
        data[at + 1] = (g * min(source, 1) + data[at + 1] * under) / out
        data[at + 2] = (b * min(source, 1) + data[at + 2] * under) / out
        data[at + 3] = out * 255
      end
    end
  end

  self.left, self.top = min(self.left, x0), min(self.top, y0)
  self.right, self.bottom = max(self.right, x1), max(self.bottom, y1)

  return self
end

local function edge(distance)
  return max(0, min(1, 0.5 - distance))
end

local function box_distance(px, py, cx, cy, half_w, half_h, radius)
  local qx, qy = abs(px - cx) - (half_w - radius), abs(py - cy) - (half_h - radius)
  local outside = sqrt(max(qx, 0) ^ 2 + max(qy, 0) ^ 2)

  return outside + min(max(qx, qy), 0) - radius
end

function Bitmap:disc(cx, cy, radius, rgb, alpha)
  return self:_fill(cx - radius - 1, cy - radius - 1, cx + radius + 1, cy + radius + 1, rgb, alpha, function(x, y)
    return edge(sqrt((x - cx) ^ 2 + (y - cy) ^ 2) - radius)
  end)
end

function Bitmap:glow(cx, cy, radius, rgb, alpha)
  if radius <= 0 then return self end

  return self:_fill(cx - radius, cy - radius, cx + radius, cy + radius, rgb, alpha, function(x, y)
    local falloff = 1 - sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / radius

    return falloff > 0 and falloff * falloff or 0
  end)
end

function Bitmap:ring(cx, cy, radius, thickness, rgb, alpha)
  local reach = radius + thickness / 2 + 1

  return self:_fill(cx - reach, cy - reach, cx + reach, cy + reach, rgb, alpha, function(x, y)
    return edge(abs(sqrt((x - cx) ^ 2 + (y - cy) ^ 2) - radius) - thickness / 2)
  end)
end

function Bitmap:arc(cx, cy, radius, thickness, from, to, rgb, alpha)
  local span = to - from

  if span <= 0 then return self end
  if span >= 1 then return self:ring(cx, cy, radius, thickness, rgb, alpha) end

  local start, half = from % 1, thickness / 2
  local reach = radius + half + 1

  local sx, sy = cx + radius * sin(from * TAU), cy - radius * cos(from * TAU)
  local ex, ey = cx + radius * sin(to * TAU), cy - radius * cos(to * TAU)

  return self:_fill(cx - reach, cy - reach, cx + reach, cy + reach, rgb, alpha, function(x, y)
    local dx, dy = x - cx, y - cy
    local along = (atan2(dx, -dy) / TAU - start) % 1
    local body = along <= span and edge(abs(sqrt(dx * dx + dy * dy) - radius) - half) or 0

    return max(body, edge(sqrt((x - sx) ^ 2 + (y - sy) ^ 2) - half), edge(sqrt((x - ex) ^ 2 + (y - ey) ^ 2) - half))
  end)
end

function Bitmap:rect(x, y, width, height, rgb, alpha, radius)
  local half_w, half_h = width / 2, height / 2
  local cx, cy = x + half_w, y + half_h

  radius = max(0, min(radius or 0, half_w, half_h))

  return self:_fill(x - 1, y - 1, x + width + 1, y + height + 1, rgb, alpha, function(px, py)
    return edge(box_distance(px, py, cx, cy, half_w, half_h, radius))
  end)
end

function Bitmap:border(x, y, width, height, thickness, rgb, alpha, radius)
  local half_w, half_h = width / 2, height / 2
  local cx, cy = x + half_w, y + half_h

  radius = max(0, min(radius or 0, half_w, half_h))

  return self:_fill(x - 1, y - 1, x + width + 1, y + height + 1, rgb, alpha, function(px, py)
    local d = box_distance(px, py, cx, cy, half_w, half_h, radius)

    return edge(abs(d + thickness / 2) - thickness / 2)
  end)
end

function Bitmap:line(x0, y0, x1, y1, thickness, rgb, alpha)
  local dx, dy = x1 - x0, y1 - y0
  local length = dx * dx + dy * dy
  local reach = thickness / 2 + 1

  return self:_fill(
    min(x0, x1) - reach,
    min(y0, y1) - reach,
    max(x0, x1) + reach,
    max(y0, y1) + reach,
    rgb,
    alpha,
    function(x, y)
      local along = length > 0 and max(0, min(1, ((x - x0) * dx + (y - y0) * dy) / length)) or 0

      return edge(sqrt((x - x0 - along * dx) ^ 2 + (y - y0 - along * dy) ^ 2) - thickness / 2)
    end
  )
end

function Bitmap:erase(x, y, width, height)
  local x0, y0 = max(0, floor(x)), max(0, floor(y))
  local x1, y1 = min(self.width - 1, floor(x + width) - 1), min(self.height - 1, floor(y + height) - 1)

  if x1 < x0 or y1 < y0 then return self end

  for row = y0, y1 do
    ffi.fill(self.data + (row * self.width + x0) * 4, (x1 - x0 + 1) * 4, 0)
  end

  return self
end

function Bitmap:crop(left, top, right, bottom)
  left, top = max(0, left), max(0, top)
  right, bottom = min(self.width - 1, right), min(self.height - 1, bottom)

  local width, height = right - left + 1, bottom - top + 1
  local out = ffi.new('uint8_t[?]', width * height * 4)

  for row = 0, height - 1 do
    ffi.copy(out + row * width * 4, self.data + ((top + row) * self.width + left) * 4, width * 4)
  end

  return ffi.string(out, width * height * 4), width, height
end

return Bitmap

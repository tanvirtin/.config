local Window = require('core.Window')
local Emitter = require('ui.anim.Emitter')
local Float = require('ui.anim.Float')

local Particles = {}

Particles.__index = Particles

Particles.Z = 240
Particles.DENSITY = 3
Particles.MAX = 400
Particles.TRAIL = 0.04

function Particles.new(spec, layer)
  if layer then
    spec = vim.tbl_extend('force', spec, {
      burst = spec.burst and spec.burst * Particles.DENSITY,
      rate = spec.rate and spec.rate * Particles.DENSITY,
      max = spec.max or Particles.MAX,
    })
  end

  return setmetatable(
    { emitter = Emitter.new(spec), pool = {}, spec = spec, normal = spec.bg, layer = layer },
    Particles
  )
end

function Particles:duration()
  local spec = self.spec

  return (spec.stop_ms or spec.start_ms or 0)
    + (type(spec.life_ms) == 'table' and spec.life_ms[2] or spec.life_ms or 800)
end

function Particles:_float(index)
  local float = self.pool[index]

  if not float then
    float = Float.new({ z = Particles.Z, normal = self.normal })
    float:set_hidden(true)
    self.pool[index] = float
  end

  return float
end

function Particles:_paint()
  local layer = self.layer
  local bitmap = layer.bitmap
  local size = self.spec.size or 1

  for _, mote in ipairs(self.emitter:motes()) do
    local fade = 1 - mote.fraction
    local rgb = layer:color(mote.hl)
    local x, y = layer:point(mote.x + 0.5, mote.y + 0.5)
    local tail_x, tail_y =
      layer:point(mote.x + 0.5 - mote.vx * Particles.TRAIL, mote.y + 0.5 - mote.vy * Particles.TRAIL)

    bitmap:glow(x, y, size * (4 + 8 * fade), rgb, 0.35 * fade)
    bitmap:line(tail_x, tail_y, x, y, size * 1.5, rgb, 0.5 * fade)
    bitmap:disc(x, y, size * (0.8 + 1.6 * fade), rgb, math.sqrt(fade))
  end
end

function Particles:update(ms)
  self.emitter:step(ms)

  if self.layer then return self:_paint() end

  local screen_w, screen_h = Window.screen_width(), Window.screen_height()
  local shown = self.emitter:particles()

  for index, p in ipairs(shown) do
    local float = self:_float(index)

    if p.x < 0 or p.y < 0 or p.x >= screen_w or p.y >= screen_h - 1 then
      float:set_hidden(true)
    else
      float:set_content({ string.format('[%s]%s[/]', p.hl, p.glyph) }, 0)
      float:place(p.x, p.y, false)
    end
  end

  for index = #shown + 1, #self.pool do
    self.pool[index]:set_hidden(true)
  end
end

function Particles:destroy()
  for _, float in ipairs(self.pool) do
    float:close()
  end

  self.pool = {}
end

return Particles

local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')
local Animation = require('ui.pixel.Animation')

local indicators = {}

indicators.KINDS = { 'spinner', 'orb', 'pulse', 'dot', 'rail' }
indicators.LINGER_MS = 500
indicators.PERIOD_MS = { spinner = 900, orb = 1600, pulse = 1400, rail = 1600 }

local CENTER = { 16, 16 }
local TURN = 2 * math.pi

local SPINNER_CENTER = { 15, 16 }
local SPINNER_RADIUS = 8
local TRAIL = 14
local SWEEP = 0.6

local DISC_RADIUS = 4
local RING_START, RING_GROW = 5, 9

local BAR_X, BAR_WIDTH, BAR_RADIUS, BAR_INSET = 6, 4, 2, 3

local animations, statics = {}, {}

function indicators.spinner(bitmap, phase, rgb)
  bitmap:ring(SPINNER_CENTER[1], SPINNER_CENTER[2], SPINNER_RADIUS, 2, rgb, 0.22)

  for step = TRAIL, 0, -1 do
    local fade = 1 - step / (TRAIL + 1)
    local angle = (phase - step / TRAIL * SWEEP) * TURN
    local x, y =
      SPINNER_CENTER[1] + math.cos(angle) * SPINNER_RADIUS, SPINNER_CENTER[2] + math.sin(angle) * SPINNER_RADIUS

    if step == 0 then bitmap:glow(x, y, 6, rgb, 0.6) end

    bitmap:disc(x, y, 1 + 0.7 * fade, rgb, fade * fade)
  end
end

function indicators.orb(bitmap, phase, rgb)
  local b = 0.5 - 0.5 * math.cos(phase * TURN)

  bitmap:glow(CENTER[1], CENTER[2], 7 + 4 * b, rgb, 0.25 + 0.25 * b)
  bitmap:disc(CENTER[1], CENTER[2], 3 + 1.5 * b, rgb, 0.75 + 0.25 * b)
end

function indicators.pulse(bitmap, phase, rgb)
  bitmap:disc(CENTER[1], CENTER[2], DISC_RADIUS, rgb, 1)
  bitmap:ring(CENTER[1], CENTER[2], RING_START + RING_GROW * phase, 2, rgb, 0.9 * (1 - phase))
end

function indicators.dot(bitmap, _, rgb)
  bitmap:disc(CENTER[1], CENTER[2], DISC_RADIUS, rgb, 1)
end

function indicators.rail(bitmap, phase, rgb)
  local b = 0.5 - 0.5 * math.cos(phase * TURN)

  bitmap:rect(BAR_X, BAR_INSET, BAR_WIDTH, bitmap.height - 2 * BAR_INSET, rgb, 0.55 + 0.45 * b, BAR_RADIUS)
end

local SPEC = {
  spinner = { cols = 2, period = indicators.PERIOD_MS.spinner, draw = indicators.spinner },
  orb = { cols = 2, period = indicators.PERIOD_MS.orb, draw = indicators.orb },
  pulse = { cols = 2, period = indicators.PERIOD_MS.pulse, draw = indicators.pulse },
  dot = { cols = 2, draw = indicators.dot },
  rail = { cols = 1, period = indicators.PERIOD_MS.rail, draw = indicators.rail },
}

local function frame(spec, role)
  if not spec.period then
    return function(bitmap)
      spec.draw(bitmap, 0, roles.rgb(role))
    end
  end

  return function(bitmap, now)
    spec.draw(bitmap, now % spec.period / spec.period, roles.rgb(role))
  end
end

function indicators.chunk(kind, role, row, rows)
  local spec = SPEC[kind]

  if not spec then
    error(string.format('unknown indicator %s (%s)', tostring(kind), table.concat(indicators.KINDS, ', ')), 0)
  end

  if not Tile.available() then return nil end

  local height = kind == 'rail' and math.max(1, rows or 1) or 1
  local key = kind .. '|' .. tostring(role) .. '|' .. height
  local index = row or 1

  if not spec.period then
    local tile = statics[key]

    if not tile then
      tile = Tile.acquire(spec.cols, height)
      tile:paint(frame(spec, role))
      statics[key] = tile
    end

    return tile:chunks(index)[1]
  end

  local animation = animations[key]

  if not animation then
    animation = Animation({
      cols = spec.cols,
      rows = height,
      linger_ms = indicators.LINGER_MS,
      draw = frame(spec, role),
    })
    animations[key] = animation
  end

  return animation:chunks(index)[1]
end

function indicators.count()
  local total = 0

  for _, animation in pairs(animations) do
    if animation:active() then total = total + 1 end
  end

  for _ in pairs(statics) do
    total = total + 1
  end

  return total
end

function indicators.stop()
  for _, animation in pairs(animations) do
    animation:stop()
  end

  for _, tile in pairs(statics) do
    tile:release()
  end

  animations, statics = {}, {}
end

return indicators

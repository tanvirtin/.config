local motion = require('ui.motion')
local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')
local Animation = require('ui.pixel.Animation')
local indicators = require('ui.pixel.indicators')

local pip = {}

pip.COLS = 2
pip.LINGER_MS = 500
pip.PERIOD_MS = indicators.PERIOD_MS.spinner
pip.BURST_MS = 450
pip.MOTES = 6
pip.TONES = { live = 'accent', done = 'added', failed = 'error' }

local CENTER = { 15, 16 }
local RADIUS = 8
local TURN = 2 * math.pi

pip.orbit = indicators.spinner

local bursts = {}

local function draw_burst(bitmap, now, animation)
  local progress = math.max(0, math.min(1, animation:elapsed(now) / pip.BURST_MS))

  pip.burst(bitmap, progress, roles.rgb(pip.TONES[animation.tone]))
end

local function prune()
  for key, burst in pairs(bursts) do
    if not burst:active() then bursts[key] = nil end
  end
end

function pip.burst(bitmap, progress, rgb)
  local out = motion.ease.out_cubic(progress)
  local fade = 1 - progress

  bitmap:glow(CENTER[1], CENTER[2], RADIUS + 6, rgb, 0.7 * fade)
  bitmap:ring(CENTER[1], CENTER[2], motion.lerp(RADIUS, RADIUS + 5, out), 2 * fade + 0.5, rgb, fade)

  for index = 1, pip.MOTES do
    local angle = index / pip.MOTES * TURN + 0.4
    local reach = motion.lerp(RADIUS - 2, RADIUS + 5, out)

    bitmap:disc(CENTER[1] + math.cos(angle) * reach, CENTER[2] + math.sin(angle) * reach, 1.4 * fade + 0.3, rgb, fade)
  end

  bitmap:disc(CENTER[1], CENTER[2], motion.lerp(RADIUS - 2, 2.5, out), rgb, 1)
end

function pip.available()
  return Tile.available()
end

function pip.live()
  local chunk = indicators.chunk('spinner', pip.TONES.live)

  return chunk and { chunk } or nil
end

function pip.finish(key, finished, now, failed)
  if not key or not finished or not now or now - finished >= pip.BURST_MS then return nil end
  if not Tile.available() then return nil end

  prune()

  local burst = bursts[key]

  if not burst then
    burst = Animation({
      cols = pip.COLS,
      started = finished,
      duration_ms = pip.BURST_MS,
      linger_ms = pip.LINGER_MS,
      draw = draw_burst,
    })
    bursts[key] = burst
  end

  burst.started, burst.tone = finished, failed and 'failed' or 'done'

  return burst:chunks()
end

function pip.count()
  prune()

  local total = 0

  for _ in pairs(bursts) do
    total = total + 1
  end

  return total
end

function pip.stop()
  indicators.stop()

  for _, burst in pairs(bursts) do
    burst:stop()
  end

  bursts = {}
end

return pip

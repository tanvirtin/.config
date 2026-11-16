local motion = require('ui.motion')
local Animation = require('ui.pixel.Animation')

local forge = {}

forge.COLS = 5
forge.LINGER_MS = 500
forge.LIFT = 0.55
forge.SPARK_SPAN = 0.45

forge.PALETTE = {
  anvil = { 0x6c, 0x70, 0x86 },
  face = { 0x93, 0x99, 0xb2 },
  handle = { 0xb0, 0x89, 0x68 },
  head = { 0xcd, 0xd6, 0xf4 },
  cold = { 0x8a, 0x2c, 0x10 },
  hot = { 0xff, 0xd8, 0x80 },
  ember = { 0xff, 0x8a, 0x30 },
  flash = { 0xff, 0xf4, 0xd0 },
}

forge.SPARKS = {
  { 150, 46 },
  { 128, 58 },
  { 108, 40 },
  { 82, 52 },
  { 62, 44 },
  { 40, 60 },
  { 24, 38 },
  { 96, 66 },
  { 140, 34 },
  { 52, 30 },
}

local PIVOT = { 66, 25 }
local REACH = 28
local REST, RAISED = 22, 38
local STRIKE = { 37, 17 }

local clock

local animation = Animation({
  cols = forge.COLS,
  draw = function(bitmap, now)
    local phase, heavy = forge.frame(now)

    forge.draw(bitmap, phase, heavy)
  end,
})

local function mix(from, to, amount)
  return {
    motion.lerp(from[1], to[1], amount),
    motion.lerp(from[2], to[2], amount),
    motion.lerp(from[3], to[3], amount),
  }
end

local function swing(phase)
  if phase < forge.LIFT then return motion.lerp(REST, RAISED, motion.ease.out_cubic(phase / forge.LIFT)) end

  return motion.lerp(RAISED, REST, motion.ease.in_cubic((phase - forge.LIFT) / (1 - forge.LIFT)))
end

local function anvil(bitmap)
  local palette = forge.PALETTE

  bitmap:rect(12, 23, 14, 3, palette.anvil, 1, 1.5)
  bitmap:rect(22, 22, 30, 5, palette.anvil, 1, 1)
  bitmap:rect(22, 22, 30, 1.5, palette.face, 1)
  bitmap:rect(31, 26, 12, 4, palette.anvil, 1)
  bitmap:rect(26, 29, 22, 3, palette.anvil, 1, 1)
end

local function ingot(bitmap, heat, heavy)
  local palette = forge.PALETTE

  bitmap:glow(STRIKE[1], 19, heavy and 22 or 16, palette.ember, 0.55 * heat)
  bitmap:rect(28, 17, 18, 5, mix(palette.cold, palette.hot, heat), 1, 1.5)
end

local function hammer(bitmap, phase)
  local palette = forge.PALETTE
  local angle = math.rad(swing(phase))
  local along_x, along_y = -math.cos(angle), -math.sin(angle)
  local head_x, head_y = PIVOT[1] + along_x * REACH, PIVOT[2] + along_y * REACH
  local across_x, across_y = -along_y, along_x

  bitmap:line(PIVOT[1], PIVOT[2], head_x, head_y, 2.5, palette.handle, 1)
  bitmap:line(
    head_x - across_x * 4,
    head_y - across_y * 4,
    head_x + across_x * 3,
    head_y + across_y * 3,
    6,
    palette.head,
    1
  )
end

function forge.sparks(bitmap, phase, heavy)
  if phase >= forge.SPARK_SPAN then return end

  local palette = forge.PALETTE
  local age = phase / forge.SPARK_SPAN
  local seconds = age * 0.5
  local count = heavy and #forge.SPARKS or 6

  for index = 1, count do
    local spark = forge.SPARKS[index]
    local angle, speed = math.rad(spark[1]), spark[2] * (heavy and 1.25 or 1)
    local x = STRIKE[1] + math.cos(angle) * speed * seconds
    local y = STRIKE[2] - math.sin(angle) * speed * seconds + 90 * seconds * seconds
    local color = mix(palette.flash, palette.ember, age)

    bitmap:glow(x, y, 4, color, 0.5 * (1 - age))
    bitmap:disc(x, y, 1.1 * (1 - age) + 0.4, color, 1 - age * age)
  end

  if age < 0.25 then bitmap:glow(STRIKE[1], STRIKE[2], heavy and 16 or 10, palette.flash, 0.9 * (1 - age / 0.25)) end
end

function forge.draw(bitmap, phase, heavy)
  local heat = (heavy and 1 or 0.8) * (1 - phase) ^ 1.5 + 0.12

  anvil(bitmap)
  ingot(bitmap, math.min(1, heat), heavy)
  hammer(bitmap, phase)
  forge.sparks(bitmap, phase, heavy)
end

function forge.frame(now)
  local beat = clock.beat
  local index = math.floor(now / beat) - math.floor((clock.started or now) / beat)

  return now % beat / beat, math.max(0, index) % clock.word_beats == 0
end

function forge.stop()
  animation:stop()
end

function forge.chunks(started, beat, word_beats)
  clock = { started = started, beat = beat, word_beats = math.max(1, word_beats or 1) }
  animation.linger_ms = forge.LINGER_MS

  return animation:chunks()
end

return forge

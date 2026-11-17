local motion = require('ui.motion')
local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')
local static = require('ui.pixel.static')
local Animation = require('ui.pixel.Animation')

local indicators = {}

indicators.KINDS = { 'busy', 'thinking', 'waiting', 'loading', 'idle', 'rail' }
indicators.ROLES =
  { busy = 'accent', thinking = 'UiThought', waiting = 'warn', loading = 'accent', idle = 'muted', rail = 'warn' }
indicators.FINISH = { done = 'added', failed = 'error' }
indicators.LINGER_MS = 500
indicators.FINISH_MS = 450
indicators.GRID = 6
indicators.INSET = 1
indicators.SPIN = { 0x0B, 0x19, 0x38, 0x34, 0x26, 0x07 }
indicators.SPIN_FRAMES = 36

local function braille(dots)
  return string.char(0xE2, 0xA0 + bit.rshift(dots, 6), 0x80 + bit.band(dots, 0x3F))
end

local function dot(i, salt, step)
  return bit.lshift(1, static.hash(i, salt, step) % 8)
end

local function distorted()
  local frames = {}

  for i = 0, indicators.SPIN_FRAMES - 1 do
    local dots = indicators.SPIN[i % #indicators.SPIN + 1]
    local h = i > 0 and static.hash(i, 7, 17) or 50

    if i > 0 and h < 12 then
      dots = bit.bor(dot(i, 1, 3), dot(i, 2, 5), dot(i, 3, 9))
    else
      if i > 0 and h < 70 then dots = bit.bor(dots, dot(i, 4, 11)) end
      if h > 85 then dots = bit.band(dots, bit.bnot(dot(i, 5, 13))) end
    end

    frames[#frames + 1] = braille(dots)
  end

  return frames
end

indicators.GLYPHS = {
  busy = distorted(),
  thinking = { '⠢', '⠔', '⠑', '⠊' },
  waiting = { '⠉', '⠒', '⠤', '⣀' },
  loading = { '⡇', '⢸' },
  idle = { '·' },
  rail = { '▎' },
}

local GRID = indicators.GRID

local animations, statics, bursts = {}, {}, {}

local function put(bitmap, x, y, rgb, alpha)
  static.block(bitmap, x, y + indicators.INSET, rgb, alpha)
end

indicators.SPIN_GRID = 12
indicators.SPIN_TURN = 12
indicators.SPIN_TAIL = 0.45

local function ring(x, y)
  local c = (indicators.SPIN_GRID - 1) / 2
  local d = math.sqrt((x - c) ^ 2 + (y - c) ^ 2)

  return d >= c - 2 and d <= c + 0.3
end

indicators.on_ring = ring

local function tear(step)
  if static.hash(step, 0, 29) >= 8 then return nil end

  return static.hash(step, 1, 31) % (indicators.SPIN_GRID - 3), 1 + static.hash(step, 2, 37) % 2
end

function indicators.busy(bitmap, step, rgb)
  local n = indicators.SPIN_GRID
  local c = (n - 1) / 2
  local head = (step % indicators.SPIN_TURN) / indicators.SPIN_TURN * 2 * math.pi
  local tail = indicators.SPIN_TAIL * 2 * math.pi
  local band, shift = tear(step)

  for y = 0, n - 1 do
    local dx = band and y >= band and y < band + 3 and shift or 0

    for x = 0, n - 1 do
      local h = static.hash(x, y, step)
      local alpha

      if ring(x, y) then
        local behind = (head - math.atan2(y - c, x - c)) % (2 * math.pi)

        if behind < tail then
          alpha = 1 - 0.85 * behind / tail
          if h < 22 then alpha = alpha * 0.35 end
        elseif h < (band and 45 or 14) then
          alpha = 0.18
        end
      elseif h < (band and 20 or 4) then
        alpha = 0.22
      end

      if alpha and x + dx < n then
        static.block(bitmap, x + dx, y + 2 * indicators.INSET, rgb, alpha, static.BLOCK / 2)
      end
    end
  end
end

function indicators.thinking(bitmap, step, rgb)
  for y = 0, GRID - 1 do
    for x = 0, GRID - 1 do
      local h = static.hash(x, y, step)

      if h < 50 then put(bitmap, x, y, rgb, 0.25 + h / 100) end
    end
  end
end

function indicators.waiting(bitmap, step, rgb)
  local line = step % GRID

  for y = 0, GRID - 1 do
    for x = 0, GRID - 1 do
      if y == line then
        put(bitmap, x, y, rgb, 1)
      elseif static.hash(x, y, 3) < 35 then
        put(bitmap, x, y, rgb, 0.2)
      end
    end
  end
end

function indicators.loading(bitmap, step, rgb)
  local col = step % GRID

  for y = 0, GRID - 1 do
    for x = 0, GRID - 1 do
      if x == col then
        put(bitmap, x, y, rgb, 1)
      elseif x < col and static.hash(x, y, 5) < 60 then
        put(bitmap, x, y, rgb, 0.5)
      elseif static.hash(x, y, step) < 20 then
        put(bitmap, x, y, rgb, 0.2)
      end
    end
  end
end

function indicators.idle(bitmap, _, rgb)
  for y = 1, GRID - 2 do
    for x = 1, GRID - 2 do
      put(bitmap, x, y, rgb, 0.5)
    end
  end
end

function indicators.rail(bitmap, step, rgb)
  local tall = math.floor(bitmap.height / static.BLOCK)
  local line = step % tall

  for y = 0, tall - 1 do
    for x = 1, 2 do
      if y == line then
        static.block(bitmap, x, y, rgb, 1)
      elseif static.hash(x, y, 3) < 60 then
        static.block(bitmap, x, y, rgb, 0.25)
      else
        static.block(bitmap, x, y, rgb, 0.12)
      end
    end
  end
end

function indicators.dissolve(bitmap, progress, rgb)
  local n = indicators.SPIN_GRID
  local fade = 1 - progress
  local snow = math.sin(math.pi * progress) * 30
  local at = math.floor(progress * 10)

  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local alpha

      if ring(x, y) and static.hash(x, y, 11) >= progress * 100 then
        alpha = fade
      elseif static.hash(x, y, at) < snow then
        alpha = 0.35 * fade
      end

      if alpha then static.block(bitmap, x, y + 2 * indicators.INSET, rgb, alpha, static.BLOCK / 2) end
    end
  end
end

local SPEC = {
  busy = { cols = 2, draw = indicators.busy },
  thinking = { cols = 2, draw = indicators.thinking },
  waiting = { cols = 2, draw = indicators.waiting },
  loading = { cols = 2, draw = indicators.loading },
  idle = { cols = 2, draw = indicators.idle, still = true },
  rail = { cols = 1, draw = indicators.rail },
}

local function refuse(kind)
  error(string.format('unknown indicator %s (%s)', tostring(kind), table.concat(indicators.KINDS, ', ')), 0)
end

local function frame(spec, role)
  if spec.still then
    return function(bitmap)
      spec.draw(bitmap, 0, roles.rgb(role))
    end
  end

  return function(bitmap, now)
    spec.draw(bitmap, motion.step(now), roles.rgb(role))
  end
end

local function draw_finish(bitmap, now, burst)
  local progress = motion.clamp(burst:elapsed(now) / indicators.FINISH_MS)

  indicators.dissolve(bitmap, progress, roles.rgb(indicators.FINISH[burst.tone]))
end

local function prune()
  for key, burst in pairs(bursts) do
    if not burst:active() then bursts[key] = nil end
  end
end

function indicators.chunk(kind, role, row, rows)
  local spec = SPEC[kind]

  if not spec then refuse(kind) end
  if not Tile.available() then return nil end

  role = role or indicators.ROLES[kind]

  local height = kind == 'rail' and math.max(1, rows or 1) or 1
  local key = kind .. '|' .. tostring(role) .. '|' .. height
  local index = row or 1

  if spec.still then
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

function indicators.finish(key, finished, now, failed)
  if not key or not finished or not now or now - finished >= indicators.FINISH_MS then return nil end
  if not Tile.available() then return nil end

  prune()

  local burst = bursts[key]

  if not burst then
    burst = Animation({
      cols = 2,
      started = finished,
      duration_ms = indicators.FINISH_MS,
      linger_ms = indicators.LINGER_MS,
      draw = draw_finish,
    })
    bursts[key] = burst
  end

  burst.started, burst.tone = finished, failed and 'failed' or 'done'

  local chunks = burst:chunks()

  return chunks and chunks[1]
end

function indicators.glyph(kind, now)
  if not SPEC[kind] then refuse(kind) end

  local frames = indicators.GLYPHS[kind]

  return frames[motion.step(now) % #frames + 1]
end

function indicators.count()
  prune()

  local total = 0

  for _, animation in pairs(animations) do
    if animation:active() then total = total + 1 end
  end

  for _ in pairs(statics) do
    total = total + 1
  end

  for _ in pairs(bursts) do
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

  for _, burst in pairs(bursts) do
    burst:stop()
  end

  animations, statics, bursts = {}, {}, {}
end

return indicators

local Emitter = {}

Emitter.__index = Emitter

Emitter.MAX = 48
Emitter.ASPECT = 2

local function range(value, fallback)
  if type(value) == 'number' then return value, value end
  if type(value) == 'table' and #value >= 2 then return value[1], value[2] end

  return fallback, fallback
end

local function list(value, fallback)
  if type(value) == 'string' then return { value } end
  if type(value) == 'table' and #value > 0 then return value end

  return fallback
end

function Emitter.new(spec)
  local instance = setmetatable({
    x = spec.at[1],
    y = spec.at[2],
    rate = spec.rate or 0,
    burst = spec.burst or 0,
    start_ms = spec.start_ms or 0,
    stop_ms = spec.stop_ms,
    gravity = spec.gravity or 0,
    drag = spec.drag or 0,
    glyphs = list(spec.glyphs, { '•' }),
    hls = list(spec.hl, { 'accent' }),
    mixed = spec.mixed == true,
    max = spec.max or Emitter.MAX,
    life = { range(spec.life_ms, 800) },
    speed = { range(spec.speed, 10) },
    angle = { range(spec.angle, 0) },
    spread = { range(spec.spread, 0) },
    live = {},
    owed = 0,
    clock = nil,
    fired = false,
  }, Emitter)

  if spec.seed then math.randomseed(spec.seed) end

  return instance
end

local function between(low, high)
  if low == high then return low end

  return low + math.random() * (high - low)
end

function Emitter:_spawn()
  if #self.live >= self.max then return end

  local speed = between(self.speed[1], self.speed[2])
  local angle = math.rad(between(self.angle[1], self.angle[2]))
  local jitter = between(self.spread[1], self.spread[2])

  self.live[#self.live + 1] = {
    x = self.x + (jitter ~= 0 and (math.random() - 0.5) * jitter or 0),
    y = self.y,
    vx = math.cos(angle) * speed * Emitter.ASPECT,
    vy = -math.sin(angle) * speed,
    age = 0,
    life = between(self.life[1], self.life[2]),
    tint = math.random(),
  }
end

function Emitter:step(now)
  local dt = self.clock and math.max(0, now - self.clock) or 0

  self.clock = now

  local seconds = dt / 1000
  local active = now >= self.start_ms and (not self.stop_ms or now <= self.stop_ms)

  if active and not self.fired then
    self.fired = true

    for _ = 1, self.burst do
      self:_spawn()
    end
  end

  if active and self.rate > 0 then
    self.owed = self.owed + self.rate * seconds

    while self.owed >= 1 do
      self.owed = self.owed - 1
      self:_spawn()
    end
  end

  local keep = {}

  for _, p in ipairs(self.live) do
    p.age = p.age + dt
    p.vy = p.vy + self.gravity * seconds
    p.vx = p.vx * (1 - math.min(1, self.drag * seconds))
    p.vy = p.vy * (1 - math.min(1, self.drag * seconds))
    p.x = p.x + p.vx * seconds
    p.y = p.y + p.vy * seconds

    if p.age < p.life then keep[#keep + 1] = p end
  end

  self.live = keep
end

function Emitter:done(now)
  return #self.live == 0 and (self.rate == 0 or (self.stop_ms ~= nil and now > self.stop_ms)) and self.fired
end

local function pick(items, fraction)
  return items[math.min(#items, math.floor(fraction * #items) + 1)]
end

function Emitter:particles()
  return vim.tbl_map(function(p)
    local fraction = p.life > 0 and p.age / p.life or 1

    return {
      x = math.floor(p.x + 0.5),
      y = math.floor(p.y + 0.5),
      glyph = pick(self.glyphs, fraction),
      hl = pick(self.hls, self.mixed and p.tint or fraction),
    }
  end, self.live)
end

function Emitter:motes()
  return vim.tbl_map(function(p)
    local fraction = p.life > 0 and p.age / p.life or 1

    return {
      x = p.x,
      y = p.y,
      vx = p.vx,
      vy = p.vy,
      fraction = fraction,
      hl = pick(self.hls, self.mixed and p.tint or fraction),
    }
  end, self.live)
end

return Emitter

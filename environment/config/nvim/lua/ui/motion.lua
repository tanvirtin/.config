local tokens = require('ui.design.motion')

local motion = {}

motion.STEP_MS = tokens.STEP_MS
motion.FRAME_MS = tokens.FRAME_MS
motion.LOOP_STEPS = tokens.LOOP_STEPS
motion.DURATION = tokens.DURATION

function motion.step(now)
  return math.floor((now or 0) / motion.STEP_MS)
end

function motion.loop(now, steps)
  return motion.step(now) % (steps or motion.LOOP_STEPS)
end

function motion.clamp(t)
  if t < 0 then return 0 end
  if t > 1 then return 1 end

  return t
end

motion.ease = {
  linear = function(t)
    return t
  end,
  out_cubic = function(t)
    return 1 - (1 - t) ^ 3
  end,
  in_out = function(t)
    if t < 0.5 then return 4 * t * t * t end

    return 1 - (-2 * t + 2) ^ 3 / 2
  end,
}

local function bounce(t)
  local n, d = 7.5625, 2.75

  if t < 1 / d then return n * t * t end
  if t < 2 / d then
    t = t - 1.5 / d
    return n * t * t + 0.75
  end
  if t < 2.5 / d then
    t = t - 2.25 / d
    return n * t * t + 0.9375
  end

  t = t - 2.625 / d

  return n * t * t + 0.984375
end

motion.ease.in_cubic = function(t)
  return t ^ 3
end

motion.ease.out_quad = function(t)
  return 1 - (1 - t) * (1 - t)
end

motion.ease.in_out_sine = function(t)
  return -(math.cos(math.pi * t) - 1) / 2
end

motion.ease.out_back = function(t)
  local c = 1.70158

  return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

motion.ease.out_bounce = bounce

motion.ease.out_elastic = function(t)
  if t <= 0 or t >= 1 then return t end

  return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
end

function motion.lerp(from, to, t)
  return from + (to - from) * t
end

function motion.steps(n, t)
  return math.min(n, math.floor(motion.clamp(t) * n) + 1)
end

function motion.breath(n, index)
  return 0.5 + 0.5 * math.cos(2 * math.pi * (index - 1) / n)
end

local Tween = {}

Tween.__index = Tween

function Tween.new(spec)
  local ease = spec.ease or 'out_cubic'

  return setmetatable({
    from = spec.from or 0,
    to = spec.to or 1,
    ms = spec.ms or 150,
    ease = type(ease) == 'function' and ease or motion.ease[ease] or motion.ease.linear,
    started = spec.started or 0,
  }, Tween)
end

function Tween:progress(now)
  if self.ms <= 0 then return 1 end

  return motion.clamp((now - self.started) / self.ms)
end

function Tween:at(now)
  return motion.lerp(self.from, self.to, self.ease(self:progress(now)))
end

function Tween:done(now)
  return self:progress(now) >= 1
end

motion.Tween = setmetatable(Tween, {
  __call = function(_, spec)
    return Tween.new(spec)
  end,
})

return motion

local motion = {}

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

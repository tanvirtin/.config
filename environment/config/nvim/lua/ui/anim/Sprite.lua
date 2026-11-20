local Float = require('ui.anim.Float')
local markup = require('ui.markup')

local Sprite = {}

Sprite.__index = Sprite

Sprite.FRAME_MS = 100

function Sprite.new(spec, tracks)
  local frames = spec.frames or { spec.lines or {} }
  local width, height = 1, 1

  for _, frame in ipairs(frames) do
    width, height = math.max(width, markup.width(frame)), math.max(height, #frame)
  end

  local instance = setmetatable({
    frames = frames,
    frame_ms = spec.frame_ms or Sprite.FRAME_MS,
    tracks = tracks,
    anchor = spec.anchor,
    width = width,
    height = height,
    at = spec.at,
  }, Sprite)

  instance.float = Float.new({
    width = width,
    height = height,
    x = instance:_left(spec.at[1]),
    y = instance:_top(spec.at[2]),
    z = spec.z,
    border = spec.border,
    blend = spec.blend,
    normal = spec.bg,
  })

  instance:update(0)

  return instance
end

function Sprite:_left(x)
  return self.anchor == 'center' and x - self.width / 2 or x
end

function Sprite:_top(y)
  return self.anchor == 'center' and y - self.height / 2 or y
end

function Sprite:duration()
  local longest = 0

  for _, track in pairs(self.tracks) do
    longest = math.max(longest, track:duration())
  end

  return longest
end

function Sprite:update(ms)
  local tick = math.floor(ms / self.frame_ms)
  local x, y = self.tracks.x, self.tracks.y

  self.float:set_content(self.frames[tick % #self.frames + 1], tick)
  self.float:move(self:_left(x and x:at(ms) or self.at[1]), self:_top(y and y:at(ms) or self.at[2]))

  if self.tracks.blend then self.float:set_blend(self.tracks.blend:at(ms)) end
end

function Sprite:destroy()
  self.float:close()
end

return Sprite

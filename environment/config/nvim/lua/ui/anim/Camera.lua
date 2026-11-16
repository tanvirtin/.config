local motion = require('ui.motion')

local Camera = {}

Camera.__index = Camera

Camera.MOVES = { 'cursor', 'scroll', 'width', 'height' }

local function ease_of(name)
  return motion.ease[name or 'in_out'] or error('unknown ease ' .. tostring(name), 0)
end

function Camera.new(spec, window)
  local move = spec.move

  if not vim.tbl_contains(Camera.MOVES, move) then
    error(string.format('unknown camera move %s (%s)', tostring(move), table.concat(Camera.MOVES, ', ')), 0)
  end

  if move == 'cursor' and type(spec.to) ~= 'table' then error('camera cursor needs to: [line, col]', 0) end
  if move ~= 'cursor' and type(spec.to) ~= 'number' then error('camera ' .. move .. ' needs to: a number', 0) end

  return setmetatable({
    move = move,
    to = spec.to,
    from_ms = spec.from_ms or 0,
    ms = spec.ms or 600,
    ease = ease_of(spec.ease),
    window = window,
    start = nil,
  }, Camera)
end

function Camera:duration()
  return self.from_ms + self.ms
end

function Camera:_origin()
  if self.move == 'cursor' then return self.window:get_cursor() end
  if self.move == 'scroll' then return self.window:get_view().topline end
  if self.move == 'width' then return self.window:get_width() end

  return self.window:get_height()
end

local function mix(from, to, t)
  return math.floor(motion.lerp(from, to, t) + 0.5)
end

function Camera:update(ms)
  if not self.window:is_valid() or ms < self.from_ms then return end

  self.start = self.start or self:_origin()

  local t = self.ease(motion.clamp((ms - self.from_ms) / math.max(self.ms, 1)))

  if self.move == 'cursor' then
    self.window:set_cursor({ mix(self.start[1], self.to[1], t), mix(self.start[2], self.to[2] or 0, t) })
  elseif self.move == 'scroll' then
    local view = self.window:get_view()

    view.topline = math.max(1, mix(self.start, self.to, t))
    self.window:set_view(view)
  elseif self.move == 'width' then
    self.window:set_width(math.max(1, mix(self.start, self.to, t)))
  else
    self.window:set_height(math.max(1, mix(self.start, self.to, t)))
  end
end

function Camera:destroy() end

return Camera

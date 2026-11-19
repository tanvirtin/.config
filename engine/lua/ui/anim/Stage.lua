local Timer = require('core.Timer')

local Stage = {}

Stage.__index = Stage

Stage.FPS = 30
Stage.MAX_MS = 30000
Stage.TAIL_MS = 50

function Stage.new(actors, opts)
  opts = opts or {}

  local longest = 0

  for _, actor in ipairs(actors) do
    longest = math.max(longest, actor:duration())
  end

  return setmetatable({
    actors = actors,
    fps = math.max(1, math.min(60, opts.fps or Stage.FPS)),
    duration = math.min(opts.duration_ms or longest + Stage.TAIL_MS, Stage.MAX_MS),
    loop = opts.loop == true,
    timer = Timer(),
    on_done = opts.on_done,
    layer = opts.layer,
    started = nil,
    stopped = false,
  }, Stage)
end

function Stage:update(ms)
  if self.stopped then return end

  local at = self.loop and self.duration > 0 and ms % self.duration or ms

  if self.layer then self.layer:begin() end

  for _, actor in ipairs(self.actors) do
    local ok, err = pcall(actor.update, actor, at)

    if not ok then return self:stop(err) end
  end

  if self.layer then self.layer:flush() end

  if not self.loop and ms >= self.duration then self:stop() end
end

function Stage:start()
  self.started = Timer.now()
  self:update(0)

  if self.stopped then return self end

  self.timer:every(math.floor(1000 / self.fps), function()
    self:update(Timer.now() - self.started)
  end)

  return self
end

function Stage:stop(err)
  if self.stopped then return end

  self.stopped = true
  self.error = err
  self.timer:close()

  for _, actor in ipairs(self.actors) do
    pcall(actor.destroy, actor)
  end

  if self.layer then pcall(self.layer.destroy, self.layer) end

  if self.on_done then self.on_done(err) end
end

function Stage:is_running()
  return not self.stopped
end

return Stage

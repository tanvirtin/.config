local Timer = require('core.Timer')
local Object = require('core.Object')
local Tile = require('ui.pixel.Tile')
local ticker = require('ui.pixel.ticker')

local Animation = Object:extend()

Animation.LINGER_MS = 500

local serial = 0

function Animation:constructor(options)
  serial = serial + 1

  return {
    key = 'ui.pixel.Animation:' .. serial,
    cols = options.cols,
    rows = options.rows or 1,
    draw = options.draw,
    linger_ms = options.linger_ms or Animation.LINGER_MS,
    duration_ms = options.duration_ms,
    started = options.started,
    seeded = false,
    last_wanted = nil,
    tile = nil,
  }
end

local function paint(animation, now)
  local at = now

  if animation.duration_ms then at = math.min(now, animation.started + animation.duration_ms) end

  animation.tile:paint(function(bitmap)
    animation.draw(bitmap, at, animation)
  end)
end

local function frame(animation, now)
  local done

  if animation.duration_ms then
    done = animation:elapsed(now) >= animation.duration_ms + animation.linger_ms
  else
    done = now - animation.last_wanted > animation.linger_ms
  end

  if done then
    animation:stop()

    return false
  end

  paint(animation, now)

  return true
end

function Animation:chunks(row)
  if not Tile.available() then return nil end

  local now = Timer.now()

  self.last_wanted = now

  if not self.tile then
    self.tile = Tile.acquire(self.cols, self.rows)

    if self.started == nil then
      self.started = now
      self.seeded = true
    end

    ticker.add(self.key, function(at)
      return frame(self, at)
    end)
    paint(self, now)
  end

  return self.tile:chunks(row)
end

function Animation:active()
  return self.tile ~= nil
end

function Animation:elapsed(now)
  if self.started == nil then return 0 end

  return now - self.started
end

function Animation:stop()
  ticker.remove(self.key)

  if self.tile then self.tile:release() end

  self.tile = nil

  if self.seeded then
    self.started = nil
    self.seeded = false
  end
end

return Animation

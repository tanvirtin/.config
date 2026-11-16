local Timer = require('core.Timer')
local Tile = require('ui.pixel.Tile')
local graphics = require('core.graphics')
local ticker = require('ui.pixel.ticker')
local Animation = require('ui.pixel.Animation')

local eq = assert.are.same

describe('ui.pixel.Animation:', function()
  local clock, deleted, animations, original

  local function animate(options)
    local animation = Animation(options)

    animations[#animations + 1] = animation

    return animation
  end

  local function painter()
    local calls = {}

    return calls,
      function(bitmap, now, animation)
        calls[#calls + 1] = { now = now, animation = animation, bitmap = bitmap }
      end
  end

  before_each(function()
    clock, deleted, animations = 0, {}, {}
    original = {
      available = Tile.available,
      now = Timer.now,
      upload = graphics.upload,
      delete = graphics.delete,
    }
    Tile.available = function()
      return true
    end
    Timer.now = function()
      return clock
    end
    graphics.upload = function() end
    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end
  end)

  after_each(function()
    for _, animation in ipairs(animations) do
      animation:stop()
    end
    ticker.stop()
    Tile.drain()
    Tile.available, Timer.now = original.available, original.now
    graphics.upload, graphics.delete = original.upload, original.delete
  end)

  it('is nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end
    local animation = animate({ cols = 2, draw = function() end })

    eq(nil, animation:chunks())
    eq(false, animation:active())
    eq(0, ticker.count())
  end)

  it('holds a tile and a ticker step from the first chunks call, and paints the first frame at once', function()
    local calls, draw = painter()
    local animation = animate({ cols = 2, draw = draw })

    local chunks = animation:chunks(1)

    eq(2, vim.fn.strdisplaywidth(chunks[1][1]))
    eq(true, animation:active())
    eq(1, ticker.count())
    eq(1, #calls)
    eq(0, calls[1].now)
    eq(animation, calls[1].animation)
  end)

  it('paints each frame at the time the ticker gives it while it is wanted', function()
    local calls, draw = painter()
    local animation = animate({ cols = 1, draw = draw })

    animation:chunks()
    clock = 100
    animation:chunks()
    ticker.step(120)

    eq(120, calls[#calls].now)
    eq(2, #calls)
  end)

  it('stops once nobody has asked for it for longer than linger_ms', function()
    local animation = animate({ cols = 1, linger_ms = 500, draw = function() end })

    animation:chunks()
    ticker.step(500)
    eq(true, animation:active())

    ticker.step(501)
    eq(false, animation:active())
    eq(0, ticker.count())
  end)

  it('keeps going while chunks keeps being asked for', function()
    local animation = animate({ cols = 1, linger_ms = 500, draw = function() end })

    animation:chunks()
    clock = 400
    animation:chunks()
    ticker.step(800)
    eq(true, animation:active())

    ticker.step(901)
    eq(false, animation:active())
  end)

  it('releases its tile on stop, and the next animation of the same size gets it', function()
    local first = animate({ cols = 2, draw = function() end })
    local group = first:chunks()[1][2]

    first:stop()

    eq(false, first:active())
    eq(0, ticker.count())
    eq(group, animate({ cols = 2, draw = function() end }):chunks()[1][2])
  end)

  it('deletes its image when it stops', function()
    local animation = animate({ cols = 1, draw = function() end })

    animation:chunks()
    ticker.step(0)
    animation:stop()

    eq(1, #deleted)
  end)

  it('measures elapsed time from the first chunks call of a run', function()
    clock = 300
    local animation = animate({ cols = 1, draw = function() end })

    eq(0, animation:elapsed(300))
    animation:chunks()
    eq(250, animation:elapsed(550))
  end)

  it('measures elapsed time from a started time given in the constructor', function()
    local animation = animate({ cols = 1, started = 100, draw = function() end })

    clock = 300
    animation:chunks()

    eq(100, animation.started)
    eq(250, animation:elapsed(350))
  end)

  it('measures elapsed time from a started time assigned before chunks', function()
    local animation = animate({ cols = 1, draw = function() end })

    animation.started = 50
    clock = 300
    animation:chunks()

    eq(50, animation.started)
    eq(300, animation:elapsed(350))
  end)

  it('starts a new run from the next chunks call after it stopped', function()
    local animation = animate({ cols = 1, draw = function() end })

    animation:chunks()
    animation:stop()
    clock = 1000
    animation:chunks()

    eq(1000, animation.started)
    eq(0, animation:elapsed(1000))
  end)

  it('runs for its duration without chunks calls, holding the last frame', function()
    local calls, draw = painter()
    local animation = animate({ cols = 1, linger_ms = 100, duration_ms = 200, draw = draw })

    animation:chunks()
    ticker.step(199)
    eq(true, animation:active())

    ticker.step(250)
    eq(200, calls[#calls].now)
    eq(true, animation:active())

    ticker.step(300)
    eq(false, animation:active())
    eq(0, ticker.count())
  end)

  it('does not stop a duration animation for lack of chunks calls before its duration', function()
    local animation = animate({ cols = 1, linger_ms = 0, duration_ms = 1000, draw = function() end })

    animation:chunks()
    ticker.step(900)

    eq(true, animation:active())
  end)

  it('passes the frame time and the animation to draw', function()
    local calls, draw = painter()
    local animation = animate({ cols = 1, draw = draw })

    clock = 10
    animation:chunks()

    eq({ now = 10, animation = animation }, { now = calls[1].now, animation = calls[1].animation })
    assert.is_truthy(calls[1].bitmap)
  end)

  it('keeps each animation on its own ticker step', function()
    local first = animate({ cols = 1, draw = function() end })
    local second = animate({ cols = 1, draw = function() end })

    first:chunks()
    second:chunks()
    eq(2, ticker.count())

    first:stop()
    eq(1, ticker.count())
    eq(true, second:active())
  end)

  it('runs on the real timer and stops when nobody asks for it', function()
    Timer.now = function()
      return vim.uv.now()
    end
    local calls, draw = painter()
    local animation = animate({ cols = 1, linger_ms = 0, draw = draw })

    animation:chunks()
    vim.wait(300, function()
      return not animation:active()
    end, 10)

    assert.is_true(#calls >= 1)
    eq(false, animation:active())
  end)
end)

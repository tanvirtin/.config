local graphics = require('core.graphics')
local Timer = require('core.Timer')
local Tile = require('ui.pixel.Tile')
local Bitmap = require('ui.pixel.Bitmap')
local ticker = require('ui.pixel.ticker')
local pip = require('harness.transcript.pip')

local eq = assert.are.same

local RGB = { 255, 200, 100 }

local function fresh()
  return Bitmap.new(pip.COLS * Tile.CELL[1], Tile.CELL[2])
end

local function picture(bitmap)
  return (bitmap:crop(0, 0, bitmap.width - 1, bitmap.height - 1))
end

local function lit(bitmap)
  local count = 0

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      if select(4, bitmap:pixel(x, y)) > 0 then count = count + 1 end
    end
  end

  return count
end

local function burst(progress)
  local bitmap = fresh()

  pip.burst(bitmap, progress, RGB)

  return bitmap
end

describe('harness.transcript.pip:', function()
  local original, uploads

  before_each(function()
    uploads = 0
    original = {
      available = Tile.available,
      upload = graphics.upload,
      delete = graphics.delete,
      burst = pip.BURST_MS,
      linger = pip.LINGER_MS,
    }
    graphics.upload = function()
      uploads = uploads + 1
    end
    graphics.delete = function() end
  end)

  after_each(function()
    pip.stop()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
    pip.BURST_MS, pip.LINGER_MS = original.burst, original.linger
  end)

  it('is nothing where there are no pixels', function()
    eq(nil, pip.live())
    eq(nil, pip.finish('a', 10, 10))
  end)

  it('orbits a different picture as the phase turns, and draws something', function()
    local start, half = fresh(), fresh()

    pip.orbit(start, 0, RGB)
    pip.orbit(half, 0.5, RGB)

    assert.is_true(lit(start) > 0)
    assert.is_true(picture(start) ~= picture(half))
  end)

  it('bursts into a wide ring, and at the end leaves only a small centre dot', function()
    assert.is_true(lit(burst(0.3)) > lit(burst(1)))
    assert.is_true(lit(burst(1)) > 0)
  end)

  it('shows the spinner as one chunk one cell pair wide, the same on every call', function()
    Tile.available = function()
      return true
    end

    local first = pip.live()
    local second = pip.live()

    eq(1, #first)
    eq(pip.COLS, vim.fn.strdisplaywidth(first[1][1]))
    eq(first, second)
    assert.is_true(uploads >= 1)
  end)

  it('bursts in a different tone from the spinner, and only just after the tool finished', function()
    Tile.available = function()
      return true
    end

    local now = Timer.now()
    local live = pip.live()
    local done = pip.finish('a', now, now)

    assert.is_true(done[1][2] ~= live[1][2])
    eq(nil, pip.finish('a', now - pip.BURST_MS, now))
    eq(nil, pip.finish(nil, now, now))
  end)

  it('keeps a burst apart for each finished tool', function()
    Tile.available = function()
      return true
    end

    local now = Timer.now()
    local first = pip.finish('a', now, now)
    local second = pip.finish('b', now, now)

    assert.is_true(first[1][2] ~= second[1][2])
    eq(2, pip.count())
  end)

  it('frees its bursts once they have played out', function()
    Tile.available = function()
      return true
    end

    pip.BURST_MS, pip.LINGER_MS = 20, 20
    pip.finish('a', Timer.now(), Timer.now())

    vim.wait(300, function()
      return pip.count() == 0
    end, 10)

    eq(0, pip.count())
  end)
end)

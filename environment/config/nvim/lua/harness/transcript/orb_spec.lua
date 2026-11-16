local graphics = require('core.graphics')
local Tile = require('ui.pixel.Tile')
local Bitmap = require('ui.pixel.Bitmap')
local ticker = require('ui.pixel.ticker')
local indicators = require('ui.pixel.indicators')
local orb = require('harness.transcript.orb')

local eq = assert.are.same

local RGB = { 255, 200, 100 }

local function fresh()
  return Bitmap.new(orb.COLS * Tile.CELL[1], Tile.CELL[2])
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

describe('harness.transcript.orb:', function()
  local original

  before_each(function()
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    graphics.upload = function() end
    graphics.delete = function() end
  end)

  after_each(function()
    orb.stop()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    eq(nil, orb.live())
  end)

  it('lights the centre of the orb and leaves its corners empty', function()
    local bitmap = fresh()

    indicators.orb(bitmap, 0.5, RGB)

    assert.is_true(select(4, bitmap:pixel(16, 16)) > 0)
    eq(0, select(4, bitmap:pixel(0, 0)))
    eq(0, select(4, bitmap:pixel(bitmap.width - 1, bitmap.height - 1)))
  end)

  it('breathes a different picture as the phase turns', function()
    local start, half = fresh(), fresh()

    indicators.orb(start, 0, RGB)
    indicators.orb(half, 0.5, RGB)

    assert.is_true(lit(start) > 0)
    assert.is_true(picture(start) ~= picture(half))
  end)

  it('shows the orb as one chunk two cells wide, the same on every call', function()
    Tile.available = function()
      return true
    end

    local first = orb.live()
    local second = orb.live()

    eq(1, #first)
    eq(orb.COLS, vim.fn.strdisplaywidth(first[1][1]))
    eq(first, second)
  end)
end)

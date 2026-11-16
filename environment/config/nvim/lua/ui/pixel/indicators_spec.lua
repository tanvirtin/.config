local Tile = require('ui.pixel.Tile')
local graphics = require('core.graphics')
local Bitmap = require('ui.pixel.Bitmap')
local ticker = require('ui.pixel.ticker')
local indicators = require('ui.pixel.indicators')

local eq = assert.are.same

local RGB = { 255, 200, 100 }
local ROLE = 'accent'

local function fresh(cols, rows)
  return Bitmap.new(cols * Tile.CELL[1], rows * Tile.CELL[2])
end

local function alpha(bitmap, x, y)
  return select(4, bitmap:pixel(x, y))
end

local function lit(bitmap)
  local count = 0

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      if alpha(bitmap, x, y) > 0 then count = count + 1 end
    end
  end

  return count
end

describe('ui.pixel.indicators:', function()
  local original, uploads

  before_each(function()
    uploads = 0
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    graphics.upload = function()
      uploads = uploads + 1
    end
    graphics.delete = function() end
    Tile.available = function()
      return true
    end
  end)

  after_each(function()
    indicators.stop()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    eq(nil, indicators.chunk('spinner', ROLE))
    eq(nil, indicators.chunk('rail', ROLE, 1, 3))
  end)

  it('refuses a kind it does not know', function()
    assert.has_error(function()
      indicators.chunk('bounce', ROLE)
    end, 'unknown indicator bounce (spinner, orb, pulse, dot, rail)')
  end)

  it('draws each kind two cells wide, and the rail one cell wide', function()
    for _, kind in ipairs({ 'spinner', 'orb', 'pulse', 'dot' }) do
      eq(2, vim.fn.strdisplaywidth(indicators.chunk(kind, ROLE)[1]))
    end

    eq(1, vim.fn.strdisplaywidth(indicators.chunk('rail', ROLE, 1, 3)[1]))
  end)

  it('shares one image between callers asking for the same indicator', function()
    local first = indicators.chunk('orb', ROLE)
    local second = indicators.chunk('orb', ROLE)

    eq(first, second)
    eq(1, uploads)
    eq(1, indicators.count())
  end)

  it('keeps a different role or rail height as its own image', function()
    indicators.chunk('orb', 'warn')
    indicators.chunk('orb', 'accent')
    indicators.chunk('rail', 'warn', 1, 1)
    indicators.chunk('rail', 'warn', 1, 3)

    eq(4, indicators.count())
  end)

  it('gives each row of a rail its own line of the same image', function()
    assert.is_true(indicators.chunk('rail', ROLE, 1, 3)[1] ~= indicators.chunk('rail', ROLE, 3, 3)[1])
    eq(1, indicators.count())
  end)

  it('lights the centre of the orb, pulse and dot and leaves the corners empty', function()
    for _, kind in ipairs({ 'orb', 'pulse', 'dot' }) do
      local bitmap = fresh(2, 1)

      indicators[kind](bitmap, 0.5, RGB)

      assert.is_true(alpha(bitmap, 16, 16) > 0, kind)
      eq(0, alpha(bitmap, 0, 0), kind)
      eq(0, alpha(bitmap, bitmap.width - 1, bitmap.height - 1), kind)
    end
  end)

  it('orbits a spinner that lights something and leaves the corners empty', function()
    local bitmap = fresh(2, 1)

    indicators.spinner(bitmap, 0.5, RGB)

    assert.is_true(lit(bitmap) > 0)
    eq(0, alpha(bitmap, 0, 0))
  end)

  it('grows the pulse ring outwards as the phase turns', function()
    local start, half = fresh(2, 1), fresh(2, 1)

    indicators.pulse(start, 0, RGB)
    indicators.pulse(half, 0.5, RGB)

    eq(0, alpha(start, 25, 16))
    assert.is_true(alpha(half, 25, 16) > 0)
  end)

  it('lights the centre column of the rail and leaves its left edge empty, breathing as it turns', function()
    local start, half = fresh(1, 1), fresh(1, 1)

    indicators.rail(start, 0, RGB)
    indicators.rail(half, 0.5, RGB)

    assert.is_true(alpha(half, 8, 16) > 0)
    eq(0, alpha(half, 0, 16))
    assert.is_true(alpha(half, 8, 16) > alpha(start, 8, 16))
  end)

  it('frees every image on stop', function()
    indicators.chunk('spinner', ROLE)
    indicators.chunk('rail', ROLE, 1, 2)
    indicators.chunk('dot', ROLE)

    eq(3, indicators.count())

    indicators.stop()

    eq(0, indicators.count())
  end)
end)

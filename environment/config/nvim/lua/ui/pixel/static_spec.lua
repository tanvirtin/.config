local Bitmap = require('ui.pixel.Bitmap')
local static = require('ui.pixel.static')

local eq = assert.are.same

local RGB = { 255, 200, 100 }

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

describe('ui.pixel.static:', function()
  it('hashes a grid cell to a number from 0 to 99 that is the same for the same inputs', function()
    for x = 0, 7 do
      for y = 0, 7 do
        local h = static.hash(x, y, 3)

        assert.is_true(h >= 0 and h <= 99)
        eq(h, static.hash(x, y, 3))
      end
    end
  end)

  it('hashes a cell differently across steps', function()
    local differs = false

    for x = 0, 7 do
      for y = 0, 7 do
        if static.hash(x, y, 1) ~= static.hash(x, y, 2) then differs = true end
      end
    end

    assert.is_true(differs)
  end)

  it('paints a block square at its grid position only', function()
    local bitmap = Bitmap.new(32, 32)

    static.block(bitmap, 1, 2, RGB, 0.5)

    assert.is_true(alpha(bitmap, 4, 8) > 0)
    assert.is_true(alpha(bitmap, 7, 11) > 0)
    eq(0, alpha(bitmap, 3, 8))
    eq(0, alpha(bitmap, 8, 8))
    eq(0, alpha(bitmap, 4, 7))
    eq(0, alpha(bitmap, 4, 12))
    eq(16, lit(bitmap))
  end)

  it('paints a block at a custom size', function()
    local bitmap = Bitmap.new(32, 32)

    static.block(bitmap, 0, 0, RGB, 1, 2)

    eq(4, lit(bitmap))
  end)

  it('lights every cell of the region at full density and none outside it', function()
    local bitmap = Bitmap.new(32, 32)

    static.noise(bitmap, 1, 1, 2, 2, 0, RGB, { density = 100 })

    eq(64, lit(bitmap))
    eq(0, alpha(bitmap, 0, 0))
    eq(0, alpha(bitmap, 31, 31))
  end)

  it('lights nothing at zero density', function()
    local bitmap = Bitmap.new(32, 32)

    static.noise(bitmap, 0, 0, 8, 8, 0, RGB, { density = 0 })

    eq(0, lit(bitmap))
  end)

  it('paints a sprite from table and function legends, skipping unknown characters', function()
    local bitmap = Bitmap.new(32, 32)
    local seen = {}

    static.sprite(bitmap, { '#x', '@.' }, {
      ['#'] = { RGB, 0.5 },
      ['@'] = function(x, y, step)
        seen[#seen + 1] = { x, y, step }

        return RGB
      end,
    }, 7)

    eq({ { 0, 1, 7 } }, seen)
    assert.is_true(alpha(bitmap, 1, 1) > 0)
    assert.is_true(alpha(bitmap, 2, 6) > 0)
    eq(0, alpha(bitmap, 6, 0))
    eq(32, lit(bitmap))
  end)

  it('honours sprite offsets and block size', function()
    local bitmap = Bitmap.new(32, 32)
    local seen = {}

    static.sprite(bitmap, { '#a', 'a#' }, {
      ['#'] = function(x, y)
        seen[#seen + 1] = { x, y }

        return RGB
      end,
    }, 0, { size = 2, ox = 3, oy = 4 })

    eq({ { 3, 4 }, { 4, 5 } }, seen)
    assert.is_true(alpha(bitmap, 6, 8) > 0)
    eq(0, alpha(bitmap, 5, 8))
    eq(8, lit(bitmap))
  end)
end)

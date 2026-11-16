local graphics = require('core.graphics')
local Tile = require('ui.pixel.Tile')
local Bitmap = require('ui.pixel.Bitmap')
local ticker = require('ui.pixel.ticker')
local forge = require('harness.transcript.forge')

local eq = assert.are.same

local function lit(bitmap)
  local count = 0

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      if select(4, bitmap:pixel(x, y)) > 0 then count = count + 1 end
    end
  end

  return count
end

local function drawn(phase, heavy)
  local bitmap = Bitmap.new(forge.COLS * Tile.CELL[1], Tile.CELL[2])

  forge.draw(bitmap, phase, heavy)

  return bitmap
end

describe('harness.transcript.forge:', function()
  local original, uploads

  before_each(function()
    uploads = 0
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    graphics.upload = function()
      uploads = uploads + 1
    end
    graphics.delete = function() end
  end)

  after_each(function()
    forge.stop()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing where there are no pixels', function()
    eq(nil, forge.chunks(0, 1200, 3))
  end)

  it('throws sparks on the blow, more on a heavy one, and none once they have died', function()
    local function sparks(phase, heavy)
      local bitmap = Bitmap.new(forge.COLS * Tile.CELL[1], Tile.CELL[2])

      forge.sparks(bitmap, phase, heavy)

      return lit(bitmap)
    end

    assert.is_true(sparks(0.3, true) > sparks(0.3, false))
    assert.is_true(sparks(0.3, false) > 0)
    eq(0, sparks(0.7, true))
  end)

  it('cools the ingot between blows', function()
    local hot = { drawn(0, true):pixel(44, 20) }
    local cold = { drawn(0.9, true):pixel(44, 20) }

    assert.is_true(hot[2] > cold[2])
  end)

  it('keeps the whole swing inside the tile', function()
    for step = 0, 20 do
      local bitmap = drawn(step / 20, true)

      for x = 0, bitmap.width - 1 do
        local _, _, _, alpha = bitmap:pixel(x, 0)

        assert.is_true(alpha < 255)
      end
    end
  end)

  it('strikes hard on the first beat of each word, and light on the rest', function()
    Tile.available = function()
      return true
    end
    forge.chunks(0, 1000, 3)

    eq({ 0.5, true }, { forge.frame(500) })
    eq({ 0.25, false }, { forge.frame(1250) })
    eq({ 0, true }, { forge.frame(3000) })
  end)

  it('paints into one tile on its own clock, and stops when the line stops asking', function()
    Tile.available = function()
      return true
    end

    forge.LINGER_MS = 30
    local first = forge.chunks(0, 1200, 3)
    local second = forge.chunks(0, 1200, 3)

    eq(forge.COLS, vim.fn.strdisplaywidth(first[1][1]))
    eq(first, second)
    assert.is_true(uploads >= 1)

    vim.wait(300, function()
      return false
    end, 10)

    local settled = uploads

    vim.wait(100, function()
      return false
    end, 10)
    eq(settled, uploads)
    forge.LINGER_MS = 500
    local restarted = uploads

    forge.chunks(0, 1200, 3)

    assert.is_true(uploads > restarted)
  end)
end)

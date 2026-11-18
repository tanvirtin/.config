local graphics = require('core.editor.graphics')
local Tile = require('ui.pixel.Tile')
local Tiles = require('ui.pixel.Tiles')

local eq = assert.are.same

local RED = { 255, 0, 0 }

local function alpha(bitmap, x, y)
  return tonumber((select(4, bitmap:pixel(x, y))))
end

describe('ui.pixel.Tiles:', function()
  local original, uploads, deleted

  before_each(function()
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    uploads, deleted = 0, {}
    Tile.available = function()
      return true
    end
    graphics.upload = function()
      uploads = uploads + 1
    end
    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end
  end)

  after_each(function()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('has pixels when the terminal can show them', function()
    eq(true, Tiles().pixels)
  end)

  it('has no pixels when the terminal cannot show them', function()
    Tile.available = function()
      return false
    end

    eq(false, Tiles().pixels)
  end)

  it('adds a tile painted once with its commands and counts it', function()
    local tiles = Tiles()
    local tile = tiles:add(1, 1, { { kind = 'rectangle', x = 0, y = 0, w = 16, h = 32, color = RED } })

    eq(1, tiles:count())
    eq(255, alpha(tile.bitmap, 8, 16))
    eq(1, uploads)
  end)

  it('adds a tile that shows the window at the offset of one larger drawing', function()
    local tiles = Tiles()
    local command = { kind = 'rectangle', x = 16, y = 0, w = 16, h = 32, color = RED }
    local left = tiles:add(1, 1, { command }, 0, 0)
    local right = tiles:add(1, 1, { command }, 16, 0)

    eq(0, alpha(left.bitmap, 8, 16))
    eq(255, alpha(right.bitmap, 8, 16))
  end)

  it('adds nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    local tiles = Tiles()

    eq(nil, tiles:add(1, 1, {}))
    eq(0, tiles:count())
    eq(0, uploads)
  end)

  it('hands out a different tile for each add', function()
    local tiles = Tiles()
    local first = tiles:add(1, 1, {})
    local second = tiles:add(1, 1, {})

    assert.is_true(first ~= second)
    eq(2, tiles:count())
  end)

  it('releases every tile, frees their images and empties the set', function()
    local tiles = Tiles()

    tiles:add(1, 1, { { kind = 'rectangle', x = 0, y = 0, w = 4, h = 4, color = RED } })
    tiles:add(2, 1, { { kind = 'rectangle', x = 0, y = 0, w = 4, h = 4, color = RED } })
    tiles:release()

    eq(0, tiles:count())
    eq(2, #deleted)
  end)

  it('releases safely when called twice', function()
    local tiles = Tiles()

    tiles:add(1, 1, { { kind = 'rectangle', x = 0, y = 0, w = 4, h = 4, color = RED } })
    tiles:release()
    tiles:release()

    eq(0, tiles:count())
    eq(1, #deleted)
  end)
end)

local graphics = require('core.graphics')
local Tile = require('ui.pixel.Tile')

local eq = assert.are.same

describe('ui.pixel.Tile:', function()
  local uploads, deleted, original

  before_each(function()
    uploads, deleted = {}, {}
    original = { upload = graphics.upload, delete = graphics.delete }
    graphics.upload = function(id, bytes, width, height, cols, rows)
      uploads[#uploads + 1] = { id = id, size = #bytes, width = width, height = height, cols = cols, rows = rows }
    end
    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end
  end)

  after_each(function()
    Tile.drain()
    graphics.upload, graphics.delete = original.upload, original.delete
  end)

  it('is a run of placeholder cells coloured with the id of its image', function()
    local tile = Tile.new(3, 2)
    local chunks = tile:chunks(2)

    eq(3, vim.fn.strdisplaywidth(chunks[1][1]))
    eq(graphics.cells(3, 2)[2], chunks[1][1])
    eq(tile.id, vim.api.nvim_get_hl(0, { name = chunks[1][2] }).fg)
    eq(0, vim.api.nvim_get_hl(0, { name = chunks[1][2] }).blend)
    eq({ 3 * Tile.CELL[1], 2 * Tile.CELL[2] }, { tile.bitmap.width, tile.bitmap.height })
  end)

  it('can give only its first cells, and all of them when asked for more', function()
    local tile = Tile.new(4, 1)

    eq(graphics.cells(2, 1)[1], tile:chunks(1, 2)[1][1])
    eq(2, vim.fn.strdisplaywidth(tile:chunks(1, 2)[1][1]))
    eq(tile:chunks(1)[1][1], tile:chunks(1, 4)[1][1])
  end)

  it('uploads what is painted, and only when the picture changed', function()
    local tile = Tile.new(2, 1)
    local function red(bitmap)
      bitmap:rect(0, 0, 4, 4, { 255, 0, 0 }, 1)
    end

    tile:paint(red):paint(red)
    eq(1, #uploads)
    eq({ id = tile.id, size = 32 * 32 * 4, width = 32, height = 32, cols = 2, rows = 1 }, uploads[1])

    tile:paint(function(bitmap)
      bitmap:rect(8, 8, 4, 4, { 255, 0, 0 }, 1)
    end)
    eq(2, #uploads)
    eq(uploads[1], uploads[2])
  end)

  it('frees its image once, and only if it sent one', function()
    local tile = Tile.new(1, 1)

    tile:destroy()
    eq({}, deleted)

    tile:paint(function() end)
    tile:destroy()
    tile:destroy()
    eq({ tile.id }, deleted)
  end)

  it('hands a released tile out again for the same size', function()
    local tile = Tile.acquire(2, 1)

    tile:release()

    eq(tile, Tile.acquire(2, 1))
  end)

  it('never hands a released tile out for another size', function()
    local tile = Tile.acquire(2, 1)

    tile:release()

    assert.is_true(Tile.acquire(3, 1) ~= tile)
    assert.is_true(Tile.acquire(2, 2) ~= tile)
  end)

  it('deletes the image of a released tile', function()
    local tile = Tile.acquire(1, 1)

    tile:paint(function(bitmap)
      bitmap:rect(0, 0, 4, 4, { 255, 0, 0 }, 1)
    end)
    tile:release()

    eq({ tile.id }, deleted)
  end)

  it('hands out a tile once per release, even when released twice', function()
    local tile = Tile.acquire(1, 1)

    tile:release():release()

    eq(tile, Tile.acquire(1, 1))
    assert.is_true(Tile.acquire(1, 1) ~= tile)
  end)

  it('forgets released tiles on drain', function()
    local tile = Tile.acquire(1, 1)

    tile:release()
    Tile.drain()

    assert.is_true(Tile.acquire(1, 1) ~= tile)
  end)
end)

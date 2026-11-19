local graphics = require('core.editor.graphics')
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
    eq({ size = 32 * 32 * 4, width = 32, height = 32, cols = 2, rows = 1 }, {
      size = uploads[1].size,
      width = uploads[1].width,
      height = uploads[1].height,
      cols = uploads[1].cols,
      rows = uploads[1].rows,
    })

    tile:paint(function(bitmap)
      bitmap:rect(8, 8, 4, 4, { 255, 0, 0 }, 1)
    end)
    eq(2, #uploads)
    assert.is_true(uploads[1].id ~= uploads[2].id)
  end)

  it('shows each picture from its own image, uploading a picture only the first time it is drawn', function()
    local tile = Tile.new(1, 1)
    local function fill(shade)
      return function(bitmap)
        bitmap:rect(0, 0, 4, 4, { shade, 0, 0 }, 1)
      end
    end
    local function shown()
      return vim.api.nvim_get_hl(0, { name = tile:chunks(1)[1][2] }).fg
    end

    tile:paint(fill(10))
    eq(uploads[1].id, shown())

    tile:paint(fill(20))
    eq(uploads[2].id, shown())

    tile:paint(fill(10))
    eq(2, #uploads)
    eq(uploads[1].id, shown())
  end)

  it('shares a picture between tiles of the same size', function()
    local function red(bitmap)
      bitmap:rect(0, 0, 4, 4, { 255, 0, 0 }, 1)
    end

    Tile.new(1, 1):paint(red)
    Tile.new(1, 1):paint(red)
    Tile.new(2, 1):paint(red)

    eq(2, #uploads)
  end)

  it('frees the picture of a still tile once no tile shows it', function()
    local function red(bitmap)
      bitmap:rect(0, 0, 4, 4, { 255, 0, 0 }, 1)
    end
    local first, second = Tile.new(1, 1):paint(red), Tile.new(1, 1):paint(red)

    first:destroy()
    eq({}, deleted)

    second:destroy()
    second:destroy()
    eq({ uploads[1].id }, deleted)
    eq(second.id, vim.api.nvim_get_hl(0, { name = second:chunks(1)[1][2] }).fg)
  end)

  it('keeps the frames of an animated tile for the next run that draws them', function()
    local tile = Tile.new(1, 1)
    local function fill(shade)
      return function(bitmap)
        bitmap:rect(0, 0, 4, 4, { shade, 0, 0 }, 1)
      end
    end

    tile:paint(fill(10)):paint(fill(20))
    tile:destroy()
    eq({}, deleted)

    Tile.new(1, 1):paint(fill(10)):paint(fill(20))
    eq(2, #uploads)
  end)

  it('frees the least recently used image no tile shows once it holds too many', function()
    local frames = Tile.FRAMES
    local function fill(shade)
      return function(bitmap)
        bitmap:rect(0, 0, 4, 4, { shade, 0, 0 }, 1)
      end
    end

    Tile.FRAMES = 2

    local still = Tile.new(1, 1):paint(fill(10))
    local moving = Tile.new(1, 1)

    moving:paint(fill(20))
    moving:paint(fill(30))
    moving:paint(fill(40))

    Tile.FRAMES = frames

    eq({ uploads[2].id }, deleted)
    eq(3, Tile.frames())
    eq(uploads[1].id, vim.api.nvim_get_hl(0, { name = still:chunks(1)[1][2] }).fg)
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

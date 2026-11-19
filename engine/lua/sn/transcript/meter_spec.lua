local Tile = require('ui.pixel.Tile')
local graphics = require('core.editor.graphics')
local meter = require('sn.transcript.meter')

local eq = assert.are.same

local GROUP = 'MeterSpecGroup'
local NO_FG = 'MeterSpecNoFg'
local ADDED_RGB = { 0x00, 0xff, 0x00 }
local REMOVED_RGB = { 0xff, 0x00, 0x00 }

local function cells(chunks)
  local total = 0

  for _, chunk in ipairs(chunks) do
    total = total + vim.fn.strdisplaywidth(chunk[1])
  end

  return total
end

local function alpha(upload, x, y)
  return string.byte(upload.bytes, (y * upload.width + x) * 4 + 4)
end

local function count_color(upload, rgb)
  local count = 0

  for i = 0, upload.width * upload.height - 1 do
    local at = i * 4
    local r, g, b = string.byte(upload.bytes, at + 1, at + 3)

    if string.byte(upload.bytes, at + 4) > 0 and r == rgb[1] and g == rgb[2] and b == rgb[3] then count = count + 1 end
  end

  return count
end

describe('sn.transcript.meter:', function()
  local original, uploads, deleted

  before_each(function()
    uploads, deleted = {}, {}
    original = {
      available = Tile.available,
      upload = graphics.upload,
      delete = graphics.delete,
      added = vim.api.nvim_get_hl(0, { name = 'UiAdded', link = false }),
      removed = vim.api.nvim_get_hl(0, { name = 'UiRemoved', link = false }),
    }
    Tile.available = function()
      return true
    end
    graphics.upload = function(id, bytes, width, height, cols)
      uploads[#uploads + 1] = { id = id, bytes = bytes, width = width, height = height, cols = cols }
    end
    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end
    vim.api.nvim_set_hl(0, GROUP, { fg = 0x808080 })
    vim.api.nvim_set_hl(0, NO_FG, { bg = 0x101010 })
    vim.api.nvim_set_hl(0, 'UiAdded', { fg = 0x00ff00 })
    vim.api.nvim_set_hl(0, 'UiRemoved', { fg = 0xff0000 })
  end)

  after_each(function()
    meter.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
    vim.api.nvim_set_hl(0, 'UiAdded', original.added)
    vim.api.nvim_set_hl(0, 'UiRemoved', original.removed)
  end)

  it('is nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    eq(nil, meter.bar(0.5, 8, GROUP))
    eq(nil, meter.diffstat(1, 1))
    eq(0, meter.count())
  end)

  it('counts the green squares of a diffstat from the share of added lines', function()
    eq(0, meter.greens(0, 0))
    eq(5, meter.greens(1, 0))
    eq(0, meter.greens(0, 1))
    eq(1, meter.greens(1, 1000))
    eq(4, meter.greens(1000, 1))
    eq(3, meter.greens(3, 3))
  end)

  it('is three cells wide for a diffstat, and nothing for no lines', function()
    eq(meter.DIFFSTAT_COLS, cells(meter.diffstat(4, 2)))
    eq(nil, meter.diffstat(0, 0))
  end)

  it('reuses the tiles of the same diffstat and adds one for a new ratio', function()
    local first = meter.diffstat(4, 2)
    local count, tiles = #uploads, meter.count()

    eq(first, meter.diffstat(4, 2))
    eq(count, #uploads)
    eq(tiles, meter.count())

    meter.diffstat(1, 4)

    eq(tiles + 1, meter.count())
  end)

  it('draws the context ring as static blocks that fill clockwise from the top', function()
    local grey = { 0x80, 0x80, 0x80 }

    eq(2, cells(meter.ring(0.45, GROUP)))

    local function drawn(share)
      meter.ring(share, GROUP)

      return uploads[#uploads]
    end

    local empty, half, full = drawn(0), drawn(0.5), drawn(1)

    local function solid(upload)
      local total = 0

      for y = 0, upload.height - 1 do
        for x = 0, upload.width - 1 do
          if alpha(upload, x, y) == 255 then total = total + 1 end
        end
      end

      return total
    end

    eq(0, solid(empty))
    assert.is_true(solid(empty) < solid(half))
    assert.is_true(solid(half) < solid(full))
    assert.is_true(count_color(empty, grey) > 0)

    local function weight(upload, from, to)
      local total = 0

      for y = 0, upload.height - 1 do
        for x = from, to do
          total = total + alpha(upload, x, y)
        end
      end

      return total
    end

    assert.is_true(weight(half, 16, 31) > weight(half, 0, 15))
    assert.is_true(weight(empty, 0, 31) > 0)
  end)

  it('shares one image per rounded percentage of the ring', function()
    local first = meter.ring(0.4, GROUP)
    local count = meter.count()

    eq(first, meter.ring(0.4, GROUP))
    eq(count, meter.count())

    meter.ring(0.7, GROUP)

    eq(count + 1, meter.count())
  end)

  it('is as wide as asked for a bar, and caches it per rounded fill', function()
    eq(8, cells(meter.bar(0.5, 8, GROUP)))
    eq(12, cells(meter.bar(0.2, 12, GROUP)))

    local count = meter.count()

    meter.bar(0.5, 8, GROUP)

    eq(count, meter.count())
  end)

  it('is nothing for a bar in a group without a foreground colour', function()
    eq(nil, meter.bar(0.5, 8, NO_FG))
    eq(nil, meter.diffstat(0, 0))
  end)

  it('lights a full bar to its right end and leaves an empty bar dark there', function()
    meter.bar(1, 8, GROUP)
    local full = uploads[#uploads]

    assert.is_true(alpha(full, full.width - 6, 16) > 200)

    meter.bar(0, 8, GROUP)
    local empty = uploads[#uploads]

    assert.is_true(alpha(empty, empty.width - 6, 16) < 200)
  end)

  it('paints no removed colour in a diffstat of only added lines', function()
    meter.diffstat(5, 0)
    local upload = uploads[#uploads]

    eq(0, count_color(upload, REMOVED_RGB))
    assert.is_true(count_color(upload, ADDED_RGB) > 0)
  end)

  it('frees every cached tile on stop', function()
    meter.bar(0.5, 8, GROUP)
    meter.diffstat(4, 2)
    meter.stop()

    eq(0, meter.count())
    eq(2, #deleted)
  end)
end)

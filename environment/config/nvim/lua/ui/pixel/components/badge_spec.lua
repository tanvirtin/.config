local Tile = require('ui.pixel.Tile')
local Tiles = require('ui.pixel.Tiles')
local badge = require('ui.pixel.components.badge')
local graphics = require('core.editor.graphics')
local highlight = require('core.editor.highlight')

local eq = assert.are.same

local FG = '#ff0000'
local NORMAL_BG = 0x101010
local TINTED = 0x450c0c
local GROUP = 'UiPixelBadgeff0000'

local function alpha(bitmap, x, y)
  return tonumber((select(4, bitmap:pixel(x, y))))
end

local function props(text)
  return { text = text, color = FG }
end

describe('ui.pixel.components.badge:', function()
  local original, normal

  before_each(function()
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
    Tile.available = function()
      return true
    end
    graphics.upload = function() end
    graphics.delete = function() end
    vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = NORMAL_BG })
  end)

  after_each(function()
    Tile.drain()
    vim.api.nvim_set_hl(0, 'Normal', normal)
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing for empty text', function()
    local tiles = Tiles()

    eq({}, badge.render(props(''), tiles))
    eq(0, tiles:count())
  end)

  it('is a left cap, the text and a right cap in one row when there are pixels', function()
    local tiles = Tiles()
    local rows = badge.render(props('ok'), tiles)

    eq(1, #rows)
    eq(3, #rows[1])
    eq({ 'ok', GROUP }, rows[1][2])
    eq(2, tiles:count())

    tiles:release()
  end)

  it('tints the group with the colour over the normal background', function()
    badge.render(props('ok'), Tiles())

    local spec = highlight.get_hl_by_name(GROUP)

    eq(0xff0000, spec.fg)
    eq(TINTED, spec.bg)
  end)

  it('paints the left cap empty in its corner and filled in the middle right', function()
    local tiles = Tiles()

    badge.render(props('ok'), tiles)

    local cap = tiles.list[1]

    eq(0, alpha(cap.bitmap, 0, 0))
    eq(255, alpha(cap.bitmap, 15, 16))

    tiles:release()
  end)

  it('starts the right cap where the text ends', function()
    local tiles = Tiles()

    badge.render(props('ok'), tiles)

    local cap = tiles.list[2]

    eq(255, alpha(cap.bitmap, 0, 16))
    eq(0, alpha(cap.bitmap, 15, 16))

    tiles:release()
  end)

  it('uses the foreground alone when the normal background is missing', function()
    vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff })

    local tiles = Tiles()
    local rows = badge.render(props('ok'), tiles)
    local spec = highlight.get_hl_by_name(GROUP)

    eq({ { { ' ok ', GROUP } } }, rows)
    eq(0, tiles:count())
    eq(0xff0000, spec.fg)
    eq(nil, spec.bg)
  end)

  it('shows the padded text alone where there are no pixels', function()
    Tile.available = function()
      return false
    end

    local tiles = Tiles()

    eq({ { { ' ok ', GROUP } } }, badge.render(props('ok'), tiles))
    eq(0, tiles:count())
  end)
end)

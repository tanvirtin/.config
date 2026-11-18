local Tile = require('ui.pixel.Tile')
local Tiles = require('ui.pixel.Tiles')
local card = require('ui.pixel.components.card')
local graphics = require('core.editor.graphics')
local markup = require('ui.markup')

local eq = assert.are.same

local function props(lines)
  return { lines = lines, color = '#ff0000' }
end

local function width(row)
  local total = 0

  for _, chunk in ipairs(row) do
    total = total + vim.fn.strdisplaywidth(chunk[1])
  end

  return total
end

describe('ui.pixel.components.card:', function()
  local original, deleted

  before_each(function()
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    deleted = 0
    Tile.available = function()
      return true
    end
    graphics.upload = function() end
    graphics.delete = function()
      deleted = deleted + 1
    end
  end)

  after_each(function()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing for no lines', function()
    local tiles = Tiles()

    eq({}, card.render(props({}), tiles))
    eq(0, tiles:count())
  end)

  it('ignores lines that are not strings', function()
    local rows = card.render(props({ 'a', 3, {} }), Tiles())

    eq(3, #rows)
  end)

  it('wraps the lines in a top row, one row each and a bottom row when there are pixels', function()
    local tiles = Tiles()
    local rows = card.render(props({ 'ab', 'c' }), tiles)

    eq(4, #rows)
    eq(4, tiles:count())
    eq({ 'c ' }, rows[3][2])
    eq(3, #rows[3])

    tiles:release()
  end)

  it('splits a border that is wider or taller than one image can be', function()
    local tiles = Tiles()
    local lines = {}

    for i = 1, Tile.MAX_CELLS + 1 do
      lines[i] = string.rep('x', Tile.MAX_CELLS)
    end

    local rows = card.render(props(lines), tiles)

    eq(Tile.MAX_CELLS + 3, #rows)
    eq(2, #rows[1])
    eq(8, tiles:count())

    for _, row in ipairs(rows) do
      eq(Tile.MAX_CELLS + 2, width(row))
    end

    tiles:release()
  end)

  it('keeps every row of a card the same width when there are no pixels', function()
    Tile.available = function()
      return false
    end

    local tiles = Tiles()
    local rows = card.render(props({ 'ab', 'c', 'defg' }), tiles)

    eq(5, #rows)
    eq(0, tiles:count())

    for _, row in ipairs(rows) do
      eq(6, width(row))
    end
  end)

  it('draws the box characters in the group of the colour when there are no pixels', function()
    Tile.available = function()
      return false
    end

    local rows = card.render(props({ 'ab' }), Tiles())

    eq({ { '╭──╮', markup.group('#ff0000') } }, rows[1])
    eq({ { '│', markup.group('#ff0000') }, { 'ab' }, { '│', markup.group('#ff0000') } }, rows[2])
    eq({ { '╰──╯', markup.group('#ff0000') } }, rows[3])
  end)

  it('frees every tile of the card on release, once', function()
    local tiles = Tiles()

    card.render(props({ 'ab', 'c' }), tiles)
    tiles:release()

    eq(0, tiles:count())
    eq(4, deleted)

    tiles:release()
    eq(4, deleted)
  end)
end)

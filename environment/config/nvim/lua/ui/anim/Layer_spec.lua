local graphics = require('core.editor.graphics')
local Layer = require('ui.anim.Layer')

local eq = assert.are.same

describe('ui.anim.Layer:', function()
  local drawn, deleted, original

  before_each(function()
    drawn, deleted = {}, {}
    original = { draw = graphics.draw, delete = graphics.delete }
    graphics.draw = function(id, bytes, width, height, place, replaced)
      drawn[#drawn + 1] = { id = id, size = #bytes, width = width, height = height, place = place, replaced = replaced }
    end
    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end
  end)

  after_each(function()
    graphics.draw, graphics.delete = original.draw, original.delete
  end)

  it('covers the screen with a fixed number of pixels a cell', function()
    local layer = Layer.new()

    eq({ vim.o.columns * Layer.CELL[1], vim.o.lines * Layer.CELL[2] }, { layer.bitmap.width, layer.bitmap.height })
    eq({ 16, 48 }, { layer:point(2, 3) })
  end)

  it('sends only the cells that were drawn on, behind the text', function()
    local layer = Layer.new():begin()

    layer.bitmap:rect(10, 20, 4, 4, { 255, 0, 0 }, 1)
    layer:flush()

    eq(1, #drawn)
    eq({ row = 2, col = 2, cols = 1, rows = 1, z = -1 }, drawn[1].place)
    eq({ Layer.CELL[1], Layer.CELL[2] }, { drawn[1].width, drawn[1].height })
    eq(drawn[1].width * drawn[1].height * 4, drawn[1].size)
  end)

  it('swaps between two images, freeing the last one, and sits in front when asked', function()
    local layer = Layer.new({ front = true })

    for _ = 1, 3 do
      layer:begin()
      layer.bitmap:rect(0, 0, 4, 4, { 255, 0, 0 }, 1)
      layer:flush()
    end

    eq({ layer.ids[1], layer.ids[2], layer.ids[1] }, { drawn[1].id, drawn[2].id, drawn[3].id })
    eq({ nil, layer.ids[1], layer.ids[2] }, { drawn[1].replaced, drawn[2].replaced, drawn[3].replaced })
    eq(Layer.Z.front, drawn[1].place.z)
  end)

  it('takes its image down when a frame is empty, and when it is destroyed', function()
    local layer = Layer.new():begin()

    layer.bitmap:rect(0, 0, 4, 4, { 255, 0, 0 }, 1)
    layer:flush():begin():flush()
    eq({ layer.ids[1] }, deleted)

    layer:begin()
    layer.bitmap:rect(0, 0, 4, 4, { 255, 0, 0 }, 1)
    layer:flush()
    layer:destroy()
    layer:destroy()
    eq({ layer.ids[1], layer.ids[2] }, deleted)
  end)

  it('reads a colour from a hex code, a style name or a number', function()
    local layer = Layer.new()

    vim.api.nvim_set_hl(0, 'UiAccent', { fg = 0x102030 })

    eq({ 0xff, 0x80, 0x00 }, layer:color('#ff8000'))
    eq({ 0x10, 0x20, 0x30 }, layer:color('accent'))
    eq({ 0, 0, 1 }, layer:color(1))
    eq({ 255, 255, 255 }, layer:color('no-such-style'))
  end)
end)

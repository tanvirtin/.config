local Bitmap = require('ui.pixel.Bitmap')

local eq = assert.are.same

local RED = { 255, 0, 0 }

describe('ui.pixel.Bitmap:', function()
  it('starts transparent and clean', function()
    local bitmap = Bitmap.new(4, 4)

    eq({ 0, 0, 0, 0 }, { bitmap:pixel(1, 1) })
    eq(false, bitmap:dirty())
  end)

  it('splits a colour into its channels', function()
    eq({ 0x12, 0x34, 0x56 }, Bitmap.rgb(0x123456))
  end)

  it('fills a rectangle, and remembers the bounds it touched', function()
    local bitmap = Bitmap.new(16, 16):rect(4, 4, 6, 4, RED, 1)

    eq({ 255, 0, 0, 255 }, { bitmap:pixel(6, 5) })
    eq({ 0, 0, 0, 0 }, { bitmap:pixel(0, 0) })
    eq(true, bitmap:dirty())
    eq({ 3, 3, 11, 9 }, { bitmap:bounds() })
  end)

  it('rounds the corners of a rectangle', function()
    local bitmap = Bitmap.new(20, 20):rect(2, 2, 16, 16, RED, 1, 6)

    eq(0, select(4, bitmap:pixel(2, 2)))
    eq(255, select(4, bitmap:pixel(10, 10)))
  end)

  it('draws a disc that is solid inside and soft at its edge', function()
    local bitmap = Bitmap.new(20, 20):disc(10, 10, 4, RED, 1)

    eq(255, select(4, bitmap:pixel(10, 10)))
    eq(0, select(4, bitmap:pixel(1, 1)))
  end)

  it('draws a ring that is hollow', function()
    local bitmap = Bitmap.new(40, 40):ring(20, 20, 10, 4, RED, 1)

    eq(0, select(4, bitmap:pixel(20, 20)))
    eq(255, select(4, bitmap:pixel(30, 20)))
  end)

  it('draws a line between two points', function()
    local bitmap = Bitmap.new(20, 20):line(2, 10, 18, 10, 2, RED, 1)

    eq(255, select(4, bitmap:pixel(10, 10)))
    eq(0, select(4, bitmap:pixel(10, 2)))
  end)

  it('glows brightest at its centre and fades to nothing', function()
    local bitmap = Bitmap.new(40, 40):glow(20, 20, 10, RED, 1)
    local centre, middle = select(4, bitmap:pixel(20, 20)), select(4, bitmap:pixel(25, 20))

    assert.is_true(centre > middle and middle > 0)
    eq(0, select(4, bitmap:pixel(35, 20)))
  end)

  it('blends a translucent colour over what is already there', function()
    local bitmap = Bitmap.new(8, 8):rect(0, 0, 8, 8, { 0, 0, 255 }, 1):rect(0, 0, 8, 8, RED, 0.5)
    local r, _, b, a = bitmap:pixel(4, 4)

    eq(255, a)
    assert.is_true(r > 120 and r < 135 and b > 120 and b < 135)
  end)

  it('clips what falls outside, and ignores an invisible colour', function()
    local bitmap = Bitmap.new(8, 8):disc(-20, -20, 3, RED, 1):rect(0, 0, 4, 4, RED, 0)

    eq(false, bitmap:dirty())
  end)

  it('clears only what it drew', function()
    local bitmap = Bitmap.new(16, 16):rect(4, 4, 4, 4, RED, 1):clear()

    eq({ 0, 0, 0, 0 }, { bitmap:pixel(5, 5) })
    eq(false, bitmap:dirty())
  end)

  it('keeps pixels outside the clip untouched', function()
    local bitmap = Bitmap.new(16, 16):clip(4, 4, 4, 4):rect(0, 0, 16, 16, RED, 1)

    eq(0, select(4, bitmap:pixel(0, 0)))
    eq(0, select(4, bitmap:pixel(8, 8)))
    eq(255, select(4, bitmap:pixel(5, 5)))
  end)

  it('paints everywhere again after unclip', function()
    local bitmap = Bitmap.new(16, 16):clip(4, 4, 4, 4):unclip():rect(0, 0, 16, 16, RED, 1)

    eq(255, select(4, bitmap:pixel(8, 8)))
  end)

  it('removes the clip when cleared', function()
    local bitmap = Bitmap.new(16, 16):clip(0, 0, 2, 2):clear():rect(0, 0, 16, 16, RED, 1)

    eq(255, select(4, bitmap:pixel(8, 8)))
  end)

  it('lights the edge of a border and leaves its centre empty', function()
    local bitmap = Bitmap.new(20, 20):border(2, 2, 12, 12, 2, RED, 1)

    eq(255, select(4, bitmap:pixel(2, 8)))
    eq(255, select(4, bitmap:pixel(2, 2)))
    eq(0, select(4, bitmap:pixel(7, 7)))
  end)

  it('keeps a border inside its box', function()
    local bitmap = Bitmap.new(20, 20):border(2, 2, 12, 12, 2, RED, 1)

    eq(0, select(4, bitmap:pixel(1, 8)))
    eq(0, select(4, bitmap:pixel(14, 8)))
    eq(0, select(4, bitmap:pixel(8, 1)))
    eq(0, select(4, bitmap:pixel(8, 14)))
  end)

  it('draws a quarter arc only between its two angles', function()
    local bitmap = Bitmap.new(40, 40):arc(20, 20, 10, 4, 0, 0.25, RED, 1)

    eq(255, select(4, bitmap:pixel(27, 12)))
    eq(0, select(4, bitmap:pixel(13, 27)))
  end)

  it('draws a full circle as the ring at each compass point', function()
    local ring = Bitmap.new(40, 40):ring(20, 20, 10, 4, RED, 1)
    local arc = Bitmap.new(40, 40):arc(20, 20, 10, 4, 0, 1, RED, 1)
    local points = { { 30, 20 }, { 20, 30 }, { 9, 20 }, { 20, 9 } }

    for _, point in ipairs(points) do
      eq({ ring:pixel(point[1], point[2]) }, { arc:pixel(point[1], point[2]) })
      eq(255, select(4, arc:pixel(point[1], point[2])))
    end
  end)

  it('draws nothing for an empty or reversed range', function()
    eq(false, Bitmap.new(40, 40):arc(20, 20, 10, 4, 0.5, 0.5, RED, 1):dirty())
    eq(false, Bitmap.new(40, 40):arc(20, 20, 10, 4, 0.6, 0.2, RED, 1):dirty())
  end)

  it('wraps an arc that crosses the top', function()
    local bitmap = Bitmap.new(40, 40):arc(20, 20, 10, 4, 0.9, 1.2, RED, 1)

    eq(255, select(4, bitmap:pixel(19, 9)))
    eq(255, select(4, bitmap:pixel(20, 9)))
    eq(0, select(4, bitmap:pixel(30, 20)))
  end)

  it('erases a rectangle to transparent, clamped to the bitmap', function()
    local bitmap = Bitmap.new(8, 8):rect(0, 0, 8, 8, RED, 1):erase(-2, -2, 4, 4)

    eq({ 0, 0, 0, 0 }, { bitmap:pixel(1, 1) })
    eq(255, select(4, bitmap:pixel(2, 2)))
    eq(255, select(4, bitmap:pixel(6, 6)))
    eq({ 0, 0, 0, 0 }, { bitmap:pixel(0, 0) })
  end)

  it('ignores an erase that lies entirely outside the bitmap', function()
    local bitmap = Bitmap.new(8, 8):rect(0, 0, 8, 8, RED, 1):erase(20, 20, 4, 4):erase(-9, 2, 4, 2)

    eq(255, select(4, bitmap:pixel(4, 4)))
    eq(255, select(4, bitmap:pixel(2, 2)))
  end)

  it('crops a region to its bytes', function()
    local bitmap = Bitmap.new(8, 8):rect(2, 2, 2, 2, RED, 1)
    local bytes, width, height = bitmap:crop(2, 2, 3, 3)

    eq({ 2, 2, 16 }, { width, height, #bytes })
    eq(string.rep('\255\0\0\255', 4), bytes)
  end)
end)

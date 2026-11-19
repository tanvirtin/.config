local paint = require('ui.pixel.paint')
local Bitmap = require('ui.pixel.Bitmap')

local eq = assert.are.same

local RED = { 255, 0, 0 }
local BLUE = { 0, 0, 255 }

local function alpha_at(bitmap, x, y)
  return select(4, bitmap:pixel(x, y))
end

describe('ui.pixel.paint:', function()
  it('lists every render command kind', function()
    eq({ 'rectangle', 'border', 'text', 'image', 'scissor_start', 'scissor_end', 'custom' }, paint.KINDS)
  end)

  it('paints a rectangle with its colour and opacity', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, {
      { kind = 'rectangle', x = 2, y = 2, w = 4, h = 4, color = RED },
      { kind = 'rectangle', x = 8, y = 8, w = 4, h = 4, color = RED, opacity = 0.5 },
    })

    eq({ 255, 0, 0, 255 }, { bitmap:pixel(3, 3) })
    assert.is_true(alpha_at(bitmap, 9, 9) > 120 and alpha_at(bitmap, 9, 9) < 135)
  end)

  it('paints a border with a default width of one pixel', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, { { kind = 'border', x = 2, y = 2, w = 8, h = 8, color = RED } })

    eq(255, alpha_at(bitmap, 2, 5))
    eq(0, alpha_at(bitmap, 5, 5))
  end)

  it('skips text and image commands', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, {
      { kind = 'text', x = 0, y = 0, w = 16, h = 16 },
      { kind = 'image', x = 0, y = 0, w = 16, h = 16 },
    })

    eq(false, bitmap:dirty())
  end)

  it('calls a custom command with the bitmap and the command', function()
    local bitmap = Bitmap.new(16, 16)
    local command = { kind = 'custom', x = 0, y = 0, w = 1, h = 1 }
    local received = {}

    command.draw = function(target, given)
      received = { target, given }
    end
    paint.run(bitmap, { command })

    assert.is_true(received[1] == bitmap)
    assert.is_true(received[2] == command)
  end)

  it('clips painting to a scissor and restores it at scissor end', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, {
      { kind = 'scissor_start', x = 0, y = 0, w = 4, h = 4 },
      { kind = 'rectangle', x = 0, y = 0, w = 16, h = 16, color = RED },
      { kind = 'scissor_end' },
      { kind = 'rectangle', x = 8, y = 8, w = 2, h = 2, color = RED },
    })

    eq(255, alpha_at(bitmap, 2, 2))
    eq(0, alpha_at(bitmap, 6, 6))
    eq(255, alpha_at(bitmap, 8, 8))
  end)

  it('intersects nested scissors and restores the outer one', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, {
      { kind = 'scissor_start', x = 0, y = 0, w = 8, h = 8 },
      { kind = 'scissor_start', x = 4, y = 4, w = 8, h = 8 },
      { kind = 'rectangle', x = 0, y = 0, w = 16, h = 16, color = RED },
      { kind = 'scissor_end' },
      { kind = 'rectangle', x = 0, y = 0, w = 16, h = 16, color = BLUE },
    })

    eq(255, alpha_at(bitmap, 5, 5))
    eq(255, alpha_at(bitmap, 2, 2))
    eq(0, alpha_at(bitmap, 9, 9))
  end)

  it('removes a scissor that was never ended', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, { { kind = 'scissor_start', x = 0, y = 0, w = 4, h = 4 } })
    bitmap:rect(0, 0, 16, 16, RED, 1)

    eq(255, alpha_at(bitmap, 10, 10))
  end)

  it('ignores a scissor end without a matching start', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, {
      { kind = 'scissor_end' },
      { kind = 'rectangle', x = 0, y = 0, w = 16, h = 16, color = RED },
    })

    eq(255, alpha_at(bitmap, 10, 10))
  end)

  it('paints commands in order so a later one covers an earlier one', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, {
      { kind = 'rectangle', x = 0, y = 0, w = 8, h = 8, color = RED },
      { kind = 'rectangle', x = 2, y = 2, w = 4, h = 4, color = BLUE },
    })

    eq({ 0, 0, 255, 255 }, { bitmap:pixel(3, 3) })
    eq({ 255, 0, 0, 255 }, { bitmap:pixel(0, 0) })
  end)

  it('paints commands shifted left and up by the offset', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, { { kind = 'rectangle', x = 10, y = 10, w = 4, h = 4, color = RED } }, 8, 8)

    eq(255, alpha_at(bitmap, 3, 3))
    eq(0, alpha_at(bitmap, 0, 0))
  end)

  it('shifts a border and a scissor by the offset', function()
    local bitmap = Bitmap.new(16, 16)

    paint.run(bitmap, {
      { kind = 'scissor_start', x = 10, y = 0, w = 4, h = 16 },
      { kind = 'border', x = 10, y = 2, w = 8, h = 8, color = RED },
      { kind = 'scissor_end' },
    }, 8, 0)

    eq(255, alpha_at(bitmap, 2, 5))
    eq(0, alpha_at(bitmap, 5, 5))
  end)

  it('leaves the caller commands unchanged when an offset is given', function()
    local bitmap = Bitmap.new(16, 16)
    local command = { kind = 'rectangle', x = 10, y = 10, w = 4, h = 4, color = RED }

    paint.run(bitmap, { command }, 8, 8)

    eq(10, command.x)
    eq(10, command.y)
  end)

  it('paints a custom command with its shifted position', function()
    local bitmap = Bitmap.new(16, 16)
    local seen

    paint.run(bitmap, {
      {
        kind = 'custom',
        x = 5,
        y = 6,
        w = 1,
        h = 1,
        draw = function(_, given)
          seen = { given.x, given.y }
        end,
      },
    }, 2, 3)

    eq({ 3, 3 }, seen)
  end)

  it('raises an error for an unknown command kind', function()
    local bitmap = Bitmap.new(16, 16)

    assert.has_error(function()
      paint.run(bitmap, { { kind = 'blur', x = 0, y = 0, w = 1, h = 1 } })
    end, 'unknown render command blur')
  end)
end)

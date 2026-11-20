local markup = require('ui.markup')
local paint = require('ui.pixel.paint')
local Bitmap = require('ui.pixel.Bitmap')
local sparkline = require('ui.pixel.components.sparkline')

local eq = assert.are.same

describe('ui.pixel.components.sparkline:', function()
  local function props_with(overrides)
    local props = {}

    for name, spec in pairs(sparkline.props) do
      props[name] = spec[2]
    end

    for name, value in pairs(overrides or {}) do
      props[name] = value
    end

    return props
  end

  local function render(overrides)
    local props = props_with(overrides)
    local width = props.cols * 16
    local bitmap = Bitmap.new(width, 32)

    return paint.run(bitmap, sparkline.commands(props, width, 32))
  end

  local function pixels(bitmap)
    return (bitmap:crop(0, 0, bitmap.width - 1, bitmap.height - 1))
  end

  local function alpha(bitmap, x, y)
    return select(4, bitmap:pixel(x, y))
  end

  local function lit(bitmap, x0, y0, x1, y1)
    for y = y0, y1 do
      for x = x0, x1 do
        if alpha(bitmap, x, y) > 0 then return true end
      end
    end

    return false
  end

  it('paints nothing for an empty series', function()
    eq(pixels(Bitmap.new(128, 32)), pixels(render({ values = {} })))
  end)

  it('lights the bottom left and top right of a rising series, not the top left', function()
    local bitmap = render({ values = { 0, 1 } })

    assert.is_true(lit(bitmap, 3, 24, 8, 29))
    assert.is_true(lit(bitmap, 118, 0, 127, 8))
    eq(false, lit(bitmap, 0, 0, 8, 8))
  end)

  it('lights the vertical middle of a flat series', function()
    local bitmap = render({ values = { 4, 4, 4 } })

    assert.is_true(lit(bitmap, 60, 15, 68, 17))
    eq(false, lit(bitmap, 0, 0, 127, 5))
  end)

  it('fills under the line only when fill is on', function()
    local peak = { 0, 10, 0 }

    eq(0, alpha(render({ values = peak, fill = false }), 64, 20))

    local filled = alpha(render({ values = peak, fill = true }), 64, 20)

    assert.is_true(filled > 30 and filled < 60)
  end)

  it('draws a dot on the last point only when dot is on', function()
    local off = alpha(render({ values = { 0, 1 }, fill = false, dot = false }), 126, 3)
    local on = alpha(render({ values = { 0, 1 }, fill = false, dot = true }), 126, 3)

    eq(0, off)
    assert.is_true(on > 0)
  end)

  it('ignores entries that are not numbers', function()
    eq(pixels(render({ values = { 0, 1 } })), pixels(render({ values = { 'x', 0, true, 1 } })))
  end)

  it('has one row and the given number of cell columns', function()
    eq({ 8, 1 }, { sparkline.size(props_with()) })
    eq({ 5, 1 }, { sparkline.size(props_with({ cols = 5 })) })
  end)

  it('is never animated', function()
    eq(false, sparkline.animated(props_with()))
  end)

  local function cells(row)
    local total = 0

    for _, chunk in ipairs(row) do
      total = total + vim.fn.strdisplaywidth(chunk[1])
    end

    return total
  end

  it('falls back to one row of glyph levels, right-aligned, scaled to the values shown', function()
    local group = markup.group('accent')
    local rows = sparkline.fallback(props_with({ values = { 0, 7 }, cols = 4 }))

    eq({ { { '  ' }, { '▁█', group } } }, rows)
    eq(4, cells(rows[1]))
  end)

  it('uses the last cols numbers only, and skips entries that are not numbers', function()
    local group = markup.group('accent')

    eq(
      { { { '▁█', group } } },
      sparkline.fallback(props_with({ values = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, cols = 2 }))
    )
    eq({ { { ' ' }, { '▁█', group } } }, sparkline.fallback(props_with({ values = { 'x', 0, 7 }, cols = 3 })))
  end)

  it('draws a flat series in the middle level, and blank cells when there are no numbers', function()
    local group = markup.group('accent')

    eq({ { { '▄▄▄', group } } }, sparkline.fallback(props_with({ values = { 4, 4, 4 }, cols = 3 })))
    eq({ { { '   ' } } }, sparkline.fallback(props_with({ values = {}, cols = 3 })))
  end)
end)

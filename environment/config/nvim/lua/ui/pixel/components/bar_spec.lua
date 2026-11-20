local markup = require('ui.markup')
local paint = require('ui.pixel.paint')
local Bitmap = require('ui.pixel.Bitmap')
local catalog = require('ui.pixel.catalog')
local bar = require('ui.pixel.components.bar')

local eq = assert.are.same

local COLS = 12
local WIDTH, HEIGHT = COLS * 16, 32
local TRACK_LEFT, TRACK_RIGHT = 2, 190
local TRACK_TOP, TRACK_BOTTOM = 13, 19
local ROW = 16
local FILL = { 255, 0, 0 }
local TRACK = { 0, 0, 255 }

local function render(overrides, now)
  local bitmap = Bitmap.new(WIDTH, HEIGHT)
  local props = catalog.resolve('bar', overrides)

  paint.run(bitmap, bar.commands(props, bitmap.width, bitmap.height, now or 0))

  return bitmap
end

local function alpha(bitmap, x, y)
  return tonumber((select(4, bitmap:pixel(x, y))))
end

local function colour(bitmap, x, y)
  local r, g, b = bitmap:pixel(x, y)

  return { tonumber(r), tonumber(g), tonumber(b) }
end

local function solid(bitmap, x, y)
  return alpha(bitmap, x, y) > 200
end

local function near(actual, expected)
  for index = 1, 3 do
    if math.abs(actual[index] - expected[index]) > 1 then return false end
  end

  return true
end

local function count(bitmap, check)
  local total = 0

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      if check(bitmap, x, y) then total = total + 1 end
    end
  end

  return total
end

local function picture(bitmap)
  return (bitmap:crop(0, 0, bitmap.width - 1, bitmap.height - 1))
end

local function stays_in_track(bitmap)
  return count(bitmap, function(image, x, y)
    return alpha(image, x, y) > 0 and (x < TRACK_LEFT or x >= TRACK_RIGHT or y < TRACK_TOP or y >= TRACK_BOTTOM)
  end) == 0
end

describe('ui.pixel.components.bar:', function()
  it('is cols wide and one row high', function()
    eq({ 12, 1 }, { bar.size(catalog.resolve('bar', nil)) })
    eq({ 5, 1 }, { bar.size(catalog.resolve('bar', { cols = 5 })) })
  end)

  it('is animated only when indeterminate', function()
    eq(false, bar.animated(catalog.resolve('bar', { value = 0.5 })))
    eq(true, bar.animated(catalog.resolve('bar', { indeterminate = true })))
  end)

  it('draws only the track at value 0, a faint band in the track colour', function()
    local bitmap = render({ track = '#0000ff', color = '#ff0000' })

    eq(0, count(bitmap, solid))
    assert.is_true(alpha(bitmap, 100, ROW) > 80 and alpha(bitmap, 100, ROW) < 100)
    assert.is_true(near(colour(bitmap, 100, ROW), TRACK))
    eq(0, alpha(bitmap, 0, ROW))
    eq(0, alpha(bitmap, 100, 0))
  end)

  it('fills half the track at 0.5 and leaves the other half to the track', function()
    local bitmap = render({ value = 0.5, track = '#0000ff', color = '#ff0000' })

    assert.is_true(solid(bitmap, 50, ROW))
    assert.is_true(near(colour(bitmap, 50, ROW), FILL))
    assert.is_false(solid(bitmap, 150, ROW))
    assert.is_false(solid(bitmap, 180, ROW))
  end)

  it('fills the whole track at 1', function()
    local bitmap = render({ value = 1, color = '#ff0000' })

    assert.is_true(solid(bitmap, 4, ROW))
    assert.is_true(solid(bitmap, 180, ROW))
    assert.is_true(solid(bitmap, TRACK_RIGHT - 1, ROW))
    assert.is_false(solid(bitmap, TRACK_RIGHT + 1, ROW))
  end)

  it('clamps a value above 1 to full and a value below 0 to empty', function()
    eq(picture(render({ value = 1 })), picture(render({ value = 3 })))
    eq(picture(render({ value = 0 })), picture(render({ value = -1 })))
  end)

  it('paints the indeterminate segment in different places at two times', function()
    local early = render({ indeterminate = true, color = '#ff0000' }, 700)
    local late = render({ indeterminate = true, color = '#ff0000' }, 1050)

    assert.is_true(solid(early, 100, ROW))
    assert.is_false(solid(early, 180, ROW))
    assert.is_true(solid(late, 180, ROW))
    assert.is_false(solid(late, 100, ROW))
  end)

  it('paints no indeterminate segment outside the track at any time', function()
    for _, now in ipairs({ 0, 350, 700, 1050, 1399, 1400, 2800 }) do
      assert.is_true(stays_in_track(render({ indeterminate = true }, now)))
    end
  end)

  it('wraps the indeterminate segment back to the start every period', function()
    eq(picture(render({ indeterminate = true }, 300)), picture(render({ indeterminate = true }, 1700)))
  end)

  local function cells(row)
    local total = 0

    for _, chunk in ipairs(row) do
      total = total + vim.fn.strdisplaywidth(chunk[1])
    end

    return total
  end

  it('falls back to glyph bars as wide as its cols when there are no pixels', function()
    local props = catalog.resolve('bar', { cols = 5, value = 0.5 })
    local rows = bar.fallback(props)

    eq({ { { '▰▰▰', markup.group('accent') }, { '▱▱', markup.group('muted') } } }, rows)
    eq({ 5, 1 }, { bar.size(props) })
    eq(5, cells(rows[1]))
  end)

  it('fills the glyph bar by rounding the value over its cols', function()
    local group = markup.group('accent')
    local muted = markup.group('muted')

    eq({ { { '▱▱▱▱', muted } } }, bar.fallback(catalog.resolve('bar', { cols = 4 })))
    eq({ { { '▰▰▰', group } } }, bar.fallback(catalog.resolve('bar', { cols = 3, value = 1 })))
    eq(
      { { { '▰▰▰', group }, { '▱▱▱▱▱▱▱▱▱', muted } } },
      bar.fallback(catalog.resolve('bar', { value = 0.25 }))
    )
    eq(
      { { { '▱▱▱▱▱', muted } } },
      bar.fallback(catalog.resolve('bar', { cols = 5, value = 0.5, indeterminate = true }))
    )
  end)
end)

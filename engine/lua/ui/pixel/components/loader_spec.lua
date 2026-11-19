local markup = require('ui.markup')
local paint = require('ui.pixel.paint')
local Bitmap = require('ui.pixel.Bitmap')
local catalog = require('ui.pixel.catalog')
local loader = require('ui.pixel.components.loader')

local eq = assert.are.same

local KINDS = { 'thinking', 'waiting', 'loading', 'idle' }
local LIST = 'thinking, waiting, loading, idle'

local function render(overrides, now)
  local bitmap = Bitmap.new(32, 32)
  local props = catalog.resolve('loader', overrides)

  paint.run(bitmap, loader.commands(props, bitmap.width, bitmap.height, now or 0))

  return bitmap
end

local function alpha(bitmap, x, y)
  return tonumber((select(4, bitmap:pixel(x, y))))
end

local function lit(bitmap)
  local total = 0

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      if alpha(bitmap, x, y) > 0 then total = total + 1 end
    end
  end

  return total
end

describe('ui.pixel.components.loader:', function()
  it('defaults to a loading loader coloured by the role of its kind', function()
    eq({ kind = 'loading', color = '' }, catalog.resolve('loader'))
  end)

  it('refuses an unknown kind, and lists the kinds it allows', function()
    assert.has_error(function()
      loader.size(catalog.resolve('loader', { kind = 'rail' }))
    end, 'unknown loader kind rail (' .. LIST .. ')')

    assert.has_error(function()
      loader.fallback(catalog.resolve('loader', { kind = 'nope' }))
    end, 'unknown loader kind nope (' .. LIST .. ')')
  end)

  it('reports a 2 by 1 size for every allowed kind', function()
    for _, kind in ipairs(KINDS) do
      eq({ 2, 1 }, { loader.size(catalog.resolve('loader', { kind = kind })) })
    end
  end)

  it('animates every kind but idle', function()
    eq(true, loader.animated(catalog.resolve('loader', { kind = 'thinking' })))
    eq(true, loader.animated(catalog.resolve('loader', { kind = 'loading' })))
    eq(false, loader.animated(catalog.resolve('loader', { kind = 'idle' })))
  end)

  it('lights pixels for every allowed kind', function()
    for _, kind in ipairs(KINDS) do
      assert.is_true(lit(render({ kind = kind }, 1000)) > 0)
    end
  end)

  it('draws idle at the component origin, in its centre', function()
    local bitmap = render({ kind = 'idle' })

    assert.is_true(alpha(bitmap, 12, 12) > 100)
    eq(0, alpha(bitmap, 0, 0))
    eq(0, alpha(bitmap, 31, 31))
  end)

  it('falls back to the still glyph of its kind, then a space, in its role', function()
    eq({ { { '⡇', markup.group('accent') }, { ' ' } } }, loader.fallback(catalog.resolve('loader', {})))
    eq({ { { '·', markup.group('muted') }, { ' ' } } }, loader.fallback(catalog.resolve('loader', { kind = 'idle' })))
    eq(
      { { { '⡇', markup.group('#ff0000') }, { ' ' } } },
      loader.fallback(catalog.resolve('loader', { color = '#ff0000' }))
    )
  end)
end)

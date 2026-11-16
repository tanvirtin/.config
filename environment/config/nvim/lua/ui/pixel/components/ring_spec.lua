local markup = require('ui.markup')
local paint = require('ui.pixel.paint')
local Bitmap = require('ui.pixel.Bitmap')
local ring = require('ui.pixel.components.ring')

local eq = assert.are.same

local RED = '#ff0000'
local GREEN = '#00ff00'

local function props(overrides)
  local filled = { value = 0, color = RED, track = GREEN, thickness = 3, indeterminate = false, period_ms = 900 }

  for key, value in pairs(overrides or {}) do
    filled[key] = value
  end

  return filled
end

local function render(overrides, now)
  local bitmap = Bitmap.new(32, 32)

  return paint.run(bitmap, ring.commands(props(overrides), 32, 32, now or 0))
end

describe('ui.pixel.components.ring:', function()
  it('shows only a faint track at value 0', function()
    local bitmap = render({ value = 0 })
    local r, _, _, a = bitmap:pixel(27, 15)

    eq(0, r)
    assert.is_true(a > 0 and a < 100)
  end)

  it('lights the right half and leaves the left half dark at value 0.5', function()
    local bitmap = render({ value = 0.5 })

    eq(255, select(4, bitmap:pixel(27, 15)))
    assert.is_true(select(1, bitmap:pixel(4, 15)) < 50)
    assert.is_true(select(4, bitmap:pixel(4, 15)) < 100)
  end)

  it('lights all four compass points at value 1', function()
    local bitmap = render({ value = 1 })

    eq(255, select(4, bitmap:pixel(27, 15)))
    eq(255, select(4, bitmap:pixel(15, 27)))
    eq(255, select(4, bitmap:pixel(4, 15)))
    eq(255, select(4, bitmap:pixel(15, 4)))
  end)

  it('moves an indeterminate arc between two times', function()
    local early = render({ indeterminate = true }, 0)
    local later = render({ indeterminate = true }, 450)

    assert.is_true(select(1, early:pixel(16, 4)) > 200)
    assert.is_true(select(1, later:pixel(16, 4)) < 50)
  end)

  it('reports a 2 by 1 size', function()
    eq({ 2, 1 }, { ring.size(props()) })
  end)

  it('animates only when indeterminate', function()
    eq(false, ring.animated(props()))
    eq(true, ring.animated(props({ indeterminate = true })))
  end)

  local function cells(row)
    local total = 0

    for _, chunk in ipairs(row) do
      total = total + vim.fn.strdisplaywidth(chunk[1])
    end

    return total
  end

  it('falls back to one glyph for its fill, then a space, when there are no pixels', function()
    local group = markup.group(RED)

    eq({ { { '○', group }, { ' ' } } }, ring.fallback(props({ value = 0 })))
    eq({ { { '◔', group }, { ' ' } } }, ring.fallback(props({ value = 0.3 })))
    eq({ { { '◑', group }, { ' ' } } }, ring.fallback(props({ value = 0.5 })))
    eq({ { { '●', group }, { ' ' } } }, ring.fallback(props({ value = 1 })))
    eq({ { { '◌', group }, { ' ' } } }, ring.fallback(props({ indeterminate = true })))
  end)

  it('makes the fallback as wide as its size', function()
    local rows = ring.fallback(props({ value = 0.7 }))

    eq(1, #rows)
    eq({ 2, 1 }, { ring.size(props()) })
    eq(2, cells(rows[1]))
  end)
end)

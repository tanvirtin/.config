local Tile = require('ui.pixel.Tile')
local graphics = require('core.graphics')
local Bitmap = require('ui.pixel.Bitmap')
local ticker = require('ui.pixel.ticker')
local indicators = require('ui.pixel.indicators')

local eq = assert.are.same

local RGB = { 255, 200, 100 }
local ROLE = 'accent'

local function fresh(cols, rows)
  return Bitmap.new(cols * Tile.CELL[1], rows * Tile.CELL[2])
end

local function alpha(bitmap, x, y)
  return select(4, bitmap:pixel(x, y))
end

local function cell(bitmap, x, y)
  return alpha(bitmap, x * 4 + 2, y * 4 + 2)
end

local function lit(bitmap)
  local count = 0

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      if alpha(bitmap, x, y) > 0 then count = count + 1 end
    end
  end

  return count
end

local function snapshot(bitmap)
  local out = {}

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      out[#out + 1] = table.concat({ bitmap:pixel(x, y) }, ',')
    end
  end

  return table.concat(out, ';')
end

describe('ui.pixel.indicators:', function()
  local original, uploads

  before_each(function()
    uploads = 0
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    graphics.upload = function()
      uploads = uploads + 1
    end
    graphics.delete = function() end
    Tile.available = function()
      return true
    end
  end)

  after_each(function()
    indicators.stop()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    eq(nil, indicators.chunk('busy', ROLE))
    eq(nil, indicators.chunk('rail', ROLE, 1, 3))
    eq(nil, indicators.finish('turn', 1000, 1100, false))
  end)

  it('refuses a kind it does not know', function()
    assert.has_error(function()
      indicators.chunk('bounce', ROLE)
    end, 'unknown indicator bounce (busy, thinking, waiting, loading, idle, rail)')

    assert.has_error(function()
      indicators.glyph('bounce', 0)
    end, 'unknown indicator bounce (busy, thinking, waiting, loading, idle, rail)')
  end)

  it('draws each kind two cells wide, and the rail one cell wide', function()
    for _, kind in ipairs({ 'thinking', 'waiting', 'loading', 'idle' }) do
      eq(2, vim.fn.strdisplaywidth(indicators.chunk(kind, ROLE)[1]))
    end

    eq(1, vim.fn.strdisplaywidth(indicators.chunk('rail', ROLE, 1, 3)[1]))
  end)

  it('shares one image between callers asking for the same indicator', function()
    local first = indicators.chunk('thinking', ROLE)
    local second = indicators.chunk('thinking', ROLE)

    eq(first, second)
    eq(1, uploads)
    eq(1, indicators.count())
  end)

  it('keeps a different role or rail height as its own image', function()
    indicators.chunk('thinking', 'warn')
    indicators.chunk('thinking', 'accent')
    indicators.chunk('rail', 'warn', 1, 1)
    indicators.chunk('rail', 'warn', 1, 3)

    eq(4, indicators.count())
  end)

  it('uses the kind role when no role is given', function()
    eq(indicators.chunk('loading', 'accent'), indicators.chunk('loading'))
  end)

  it('gives each row of a rail its own line of the same image', function()
    assert.is_true(indicators.chunk('rail', ROLE, 1, 3)[1] ~= indicators.chunk('rail', ROLE, 3, 3)[1])
    eq(1, indicators.count())
  end)

  it('lights something in every animated drawing', function()
    for _, kind in ipairs({ 'busy', 'thinking', 'waiting', 'loading' }) do
      local bitmap = fresh(2, 1)

      indicators[kind](bitmap, 3, RGB)

      assert.is_true(lit(bitmap) > 0, kind)
    end

    local rail = fresh(1, 1)

    indicators.rail(rail, 3, RGB)

    assert.is_true(lit(rail) > 0)
  end)

  it('spins busy as a ring of pixels, brightest at the head', function()
    assert.is_truthy(indicators.chunk('busy', ROLE))
    eq(1, indicators.count())

    local start, later = fresh(2, 1), fresh(2, 1)

    indicators.busy(start, 0, RGB)
    indicators.busy(later, 3, RGB)

    assert.is_true(lit(start) > 0)
    assert.is_true(snapshot(start) ~= snapshot(later))
  end)

  it('moves the bright row of waiting with the step', function()
    local start, later = fresh(2, 1), fresh(2, 1)

    indicators.waiting(start, 0, RGB)
    indicators.waiting(later, 3, RGB)

    eq(255, cell(start, 0, 1))
    eq(255, cell(later, 0, 4))
    assert.is_true(cell(later, 0, 1) < 255)
  end)

  it('moves the bright column of loading with the step', function()
    local start, later = fresh(2, 1), fresh(2, 1)

    indicators.loading(start, 2, RGB)
    indicators.loading(later, 5, RGB)

    for y = 1, 6 do
      eq(255, cell(start, 2, y))
      eq(255, cell(later, 5, y))
    end

    assert.is_true(cell(later, 2, 1) < 255)
  end)

  it('draws idle the same at any step', function()
    local early, late = fresh(2, 1), fresh(2, 1)

    indicators.idle(early, 0, RGB)
    indicators.idle(late, 9, RGB)

    eq(snapshot(early), snapshot(late))
  end)

  it('draws static in whole 4x4 blocks, leaving a gap before the text', function()
    local bitmap = fresh(2, 1)

    indicators.thinking(bitmap, 5, RGB)

    for by = 0, 7 do
      for bx = 0, 7 do
        local x, y = bx * 4, by * 4
        local corner = alpha(bitmap, x, y)

        eq(corner, alpha(bitmap, x + 3, y))
        eq(corner, alpha(bitmap, x, y + 3))
        eq(corner, alpha(bitmap, x + 3, y + 3))
      end
    end

    for y = 0, bitmap.height - 1 do
      for x = 24, 31 do
        eq(0, alpha(bitmap, x, y))
      end
    end
  end)

  it('is solid in the centre of a dissolve at progress 0 and empty at progress 1', function()
    local start, done = fresh(2, 1), fresh(2, 1)

    indicators.dissolve(start, 0, RGB)
    indicators.dissolve(done, 1, RGB)

    assert.is_true(alpha(start, 16, 16) > 0)
    eq(0, lit(done))
  end)

  it('gives a finish one two-cell chunk while it is fresh', function()
    local chunk = indicators.finish('turn', 1000, 1100, false)

    eq(2, vim.fn.strdisplaywidth(chunk[1]))
  end)

  it('ends a finish once FINISH_MS has passed', function()
    eq(nil, indicators.finish('turn', 1000, 1000 + indicators.FINISH_MS, false))
  end)

  it('gives each finish key its own image and counts it', function()
    local first = indicators.finish('turn', 1000, 1100, false)
    local second = indicators.finish('tool', 1000, 1100, true)

    assert.is_true(first[2] ~= second[2])
    eq(2, indicators.count())
  end)

  it('cycles the glyph frames with the step clock', function()
    eq(indicators.GLYPHS.busy[1], indicators.glyph('busy', 0))
    eq(indicators.GLYPHS.busy[2], indicators.glyph('busy', 100))
    eq(indicators.GLYPHS.busy[1], indicators.glyph('busy', 100 * indicators.SPIN_FRAMES))
    eq('⠋', indicators.GLYPHS.busy[1])
    eq(indicators.GLYPHS.busy[1], indicators.glyph('busy', nil))
  end)

  it('frees every image on stop', function()
    indicators.chunk('thinking', ROLE)
    indicators.chunk('rail', ROLE, 1, 2)
    indicators.chunk('idle', ROLE)

    eq(3, indicators.count())

    indicators.stop()

    eq(0, indicators.count())
  end)
end)

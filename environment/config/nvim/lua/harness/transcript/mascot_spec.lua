local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')
local graphics = require('core.editor.graphics')
local Bitmap = require('ui.pixel.Bitmap')
local ticker = require('ui.pixel.ticker')
local mascot = require('harness.transcript.mascot')

local eq = assert.are.same

local function lit(bitmap, rgb)
  local count = 0

  for y = 0, bitmap.height - 1 do
    for x = 0, bitmap.width - 1 do
      local r, g, b, a = bitmap:pixel(x, y)

      if a > 0 and (not rgb or (r == rgb[1] and g == rgb[2] and b == rgb[3] and a == 255)) then count = count + 1 end
    end
  end

  return count
end

local function drawn(kind, step, form, wane)
  local bitmap = Bitmap.new(mascot.COLS * Tile.CELL[1], Tile.CELL[2])

  mascot.draw(bitmap, step, kind, form or 1, wane or 0)

  return bitmap
end

local function body_drawn(form)
  local bitmap = Bitmap.new(mascot.COLS * Tile.CELL[1], Tile.CELL[2])

  mascot.body(bitmap, 10, roles.rgb(mascot.BODY), mascot.pose(10, 'work', form, 0))

  return bitmap
end

describe('harness.transcript.mascot:', function()
  local original, uploads

  before_each(function()
    uploads = 0
    original = {
      available = Tile.available,
      upload = graphics.upload,
      delete = graphics.delete,
      grace = mascot.GRACE_MS,
      wane = mascot.WANE_MS,
      hold = mascot.HOLD_MS,
    }
    graphics.upload = function()
      uploads = uploads + 1
    end
    graphics.delete = function() end
  end)

  after_each(function()
    mascot.stop()
    ticker.stop()
    Tile.drain()
    mascot.GRACE_MS, mascot.WANE_MS, mascot.HOLD_MS = original.grace, original.wane, original.hold
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    eq(nil, mascot.chunks('work', {}))
  end)

  it('fits its art in the tile, on blocks of two pixels', function()
    local width, height = mascot.COLS * Tile.CELL[1], Tile.CELL[2]

    for _, line in ipairs(mascot.ART) do
      eq(#mascot.ART[1], #line)
      assert.is_true(#line * mascot.BLOCK <= width)
    end

    assert.is_true((#mascot.ART + 1) * mascot.BLOCK <= height)
  end)

  it('forms out of loose static, and grows eyes once it is whole', function()
    local eyes = roles.rgb(mascot.EYES.work)

    assert.is_true(lit(body_drawn(0.3)) < lit(body_drawn(1)))
    eq(0, lit(drawn('work', 10, 0.5), eyes))
    eq(12 * mascot.BLOCK * mascot.BLOCK, lit(drawn('work', 10, 1), eyes))
  end)

  it('flickers as live static from one step to the next', function()
    local one, two = drawn('work', 10), drawn('work', 11)

    assert.are_not.same(one:crop(0, 0, 47, 31), two:crop(0, 0, 47, 31))
  end)

  it('blinks its visor to a slit, and holds it open and still while it waits on you', function()
    local eyes = roles.rgb(mascot.EYES.work)
    local open, shut = lit(drawn('work', 10), eyes), lit(drawn('work', 0), eyes)

    eq(open / 2, shut)

    local wait = roles.rgb(mascot.EYES.wait)

    eq(lit(drawn('wait', 10), wait), lit(drawn('wait', 45), wait))
  end)

  it('narrows its visor to a slit in the error colour when the turn fails', function()
    local fail = roles.rgb(mascot.EYES.fail)

    eq(6 * mascot.BLOCK * mascot.BLOCK, lit(drawn('fail', 10), fail))
  end)

  it('dissolves back into static as it wanes, losing its eyes on the way', function()
    local eyes = roles.rgb(mascot.EYES.work)
    local whole, half, gone = drawn('work', 10), drawn('work', 10, 1, 0.6), drawn('work', 10, 1, 1)

    assert.is_true(lit(gone) < lit(whole))
    eq(0, lit(half, eyes))
    eq(0, lit(gone, eyes))
  end)

  it('rests between acts, then plays all five in a shuffled order without repeating one', function()
    local length = mascot.REST_STEPS + mascot.ACT_STEPS
    local seen, previous = {}, nil

    eq(nil, mascot.act(0))

    for cycle = 0, 24 do
      local name = mascot.act(cycle * length + mascot.REST_STEPS)

      assert.are_not.equal(previous, name)
      seen[name] = (seen[name] or 0) + 1
      previous = name
    end

    for _, name in ipairs(mascot.ACTS) do
      eq(5, seen[name])
    end
  end)

  it('moves through every act, and keeps still while it waits on you', function()
    local real = mascot.act

    for _, name in ipairs(mascot.ACTS) do
      local moved = false

      for at = 0, mascot.ACT_STEPS - 1 do
        mascot.act = function()
          return name, at / mascot.ACT_STEPS, 3
        end

        local pose = mascot.pose(25 + at, 'work', 1, 0)

        moved = moved
          or pose.dx ~= 0
          or pose.tear ~= nil
          or pose.scan ~= nil
          or pose.form < 1
          or pose.wane > 0
          or pose.wrap == true
      end

      mascot.act = real
      assert.is_true(moved, name)
    end

    local still = mascot.pose(mascot.REST_STEPS + 5, 'wait', 1, 0)

    eq({ 0, 0, nil, nil }, { still.dx, still.dy, still.act, still.tear })
  end)

  it('paints into one tile on its own clock, wanes for its owner alone, and stops when nobody asks', function()
    Tile.available = function()
      return true
    end

    mascot.GRACE_MS, mascot.WANE_MS, mascot.HOLD_MS = 30, 40, 20

    local doc = {}
    local first = mascot.chunks('work', doc)
    local second = mascot.chunks('work', doc)

    eq(mascot.COLS, vim.fn.strdisplaywidth(first[1][1]))
    eq(first, second)
    eq(first, mascot.idle_chunks(doc))
    assert.is_true(mascot.waning(doc))
    assert.is_false(mascot.waning({}))
    assert.is_nil(mascot.idle_chunks({}))
    assert.is_true(uploads >= 1)

    vim.wait(300, function()
      return false
    end, 10)

    assert.is_false(mascot.waning(doc))
    eq(nil, mascot.idle_chunks(doc))

    local settled = uploads

    mascot.chunks('work', doc)

    assert.is_true(mascot.waning(doc))
    eq(settled, uploads)
  end)

  it('reforms over the frames it already sent, without a single new upload', function()
    Tile.available = function()
      return true
    end

    mascot.GRACE_MS, mascot.WANE_MS, mascot.HOLD_MS = 30, 240, 20

    local doc, rounds = {}, {}

    local function appear(ms)
      mascot.chunks('work', doc)

      vim.wait(ms, function()
        mascot.chunks('work', doc)
        return false
      end, 20)

      vim.wait(mascot.GRACE_MS + mascot.WANE_MS + mascot.HOLD_MS + 60, function()
        return false
      end, 20)

      rounds[#rounds + 1] = uploads
    end

    appear(mascot.FORM_MS + 60)
    appear(mascot.FORM_MS - 60)

    assert.is_true(rounds[1] > 0)
    eq(rounds[1], rounds[2])
  end)
end)

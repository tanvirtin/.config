local Emitter = require('ui.anim.Emitter')

local eq = assert.are.same

describe('ui.anim.Emitter:', function()
  it('fires a burst once, as soon as it starts', function()
    local emitter = Emitter.new({ at = { 10, 10 }, burst = 5, life_ms = 1000, speed = 0, seed = 1 })

    emitter:step(0)
    eq(5, #emitter:particles())
    emitter:step(100)
    eq(5, #emitter:particles())
  end)

  it('waits for its start, and sends particles at its rate until it stops', function()
    local emitter = Emitter.new({ at = { 0, 0 }, rate = 100, start_ms = 100, stop_ms = 300, life_ms = 5000, seed = 1 })

    emitter:step(0)
    eq(0, #emitter:particles())
    emitter:step(100)
    eq(10, #emitter:particles())
    emitter:step(200)
    eq(20, #emitter:particles())
    emitter:step(300)
    emitter:step(1000)
    eq(30, #emitter:particles())
  end)

  it('flies along its angle, scaled for tall cells, and falls with gravity', function()
    local emitter = Emitter.new({ at = { 10, 10 }, burst = 1, life_ms = 5000, speed = 10, angle = 0, seed = 1 })

    emitter:step(0)
    emitter:step(1000)
    eq({ { x = 30, y = 10, glyph = '•', hl = 'accent' } }, emitter:particles())

    local falling = Emitter.new({ at = { 0, 0 }, burst = 1, life_ms = 5000, speed = 0, gravity = 10, seed = 1 })

    falling:step(0)
    falling:step(1000)
    assert.is_true(falling:particles()[1].y >= 9)
  end)

  it('goes up at 90 degrees', function()
    local emitter = Emitter.new({ at = { 10, 10 }, burst = 1, life_ms = 5000, speed = 4, angle = 90, seed = 1 })

    emitter:step(0)
    emitter:step(1000)
    eq({ x = 10, y = 6 }, { x = emitter:particles()[1].x, y = emitter:particles()[1].y })
  end)

  it('walks its glyphs and colours as a particle ages, then drops it', function()
    local emitter = Emitter.new({
      at = { 0, 0 },
      burst = 1,
      life_ms = 300,
      speed = 0,
      glyphs = { 'a', 'b', 'c' },
      hl = { 'warn', 'muted' },
      seed = 1,
    })

    emitter:step(0)
    eq({ 'a', 'warn' }, { emitter:particles()[1].glyph, emitter:particles()[1].hl })
    emitter:step(150)
    eq({ 'b', 'muted' }, { emitter:particles()[1].glyph, emitter:particles()[1].hl })
    emitter:step(400)
    eq({}, emitter:particles())
    assert.is_true(emitter:done(400))
  end)

  it('never holds more than its cap', function()
    local emitter = Emitter.new({ at = { 0, 0 }, burst = 500, life_ms = 5000, seed = 1 })

    emitter:step(0)
    eq(Emitter.MAX, #emitter:particles())
  end)
end)

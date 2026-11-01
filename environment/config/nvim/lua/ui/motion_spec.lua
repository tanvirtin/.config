local motion = require('ui.motion')

local eq = assert.are.same

describe('ui.motion:', function()
  it('eases from 0 to 1 and hits both ends', function()
    for _, name in ipairs({ 'linear', 'out_cubic', 'in_out' }) do
      eq(0, motion.ease[name](0))
      eq(1, motion.ease[name](1))
    end
  end)

  it('starts fast with out_cubic and slow with in_out', function()
    assert.is_true(motion.ease.out_cubic(0.25) > 0.25)
    assert.is_true(motion.ease.in_out(0.25) < 0.25)
    eq(0.5, motion.ease.in_out(0.5))
  end)

  it('lerps between two numbers', function()
    eq(5, motion.lerp(0, 10, 0.5))
    eq(10, motion.lerp(10, 20, 0))
  end)

  it('quantises progress into n steps', function()
    eq(1, motion.steps(4, 0))
    eq(2, motion.steps(4, 0.25))
    eq(4, motion.steps(4, 0.99))
    eq(4, motion.steps(4, 1))
    eq(1, motion.steps(4, -3))
  end)

  it('breathes from full to the trough and back', function()
    eq(1, motion.breath(12, 1))
    assert.is_true(math.abs(motion.breath(12, 7)) < 1e-9)
    assert.is_true(math.abs(motion.breath(12, 2) - motion.breath(12, 12)) < 1e-9)
  end)

  describe('Tween', function()
    it('moves from the start value to the end over its duration', function()
      local tween = motion.Tween({ from = 0, to = 10, ms = 100, ease = 'linear', started = 1000 })

      eq(0, tween:at(1000))
      eq(5, tween:at(1050))
      eq(10, tween:at(1100))
      eq(10, tween:at(5000))
      eq(0, tween:at(0))
    end)

    it('says when it is done', function()
      local tween = motion.Tween({ ms = 100, started = 0 })

      assert.is_false(tween:done(99))
      assert.is_true(tween:done(100))
    end)

    it('snaps to the end when it has no duration', function()
      local tween = motion.Tween({ from = 3, to = 9, ms = 0 })

      eq(9, tween:at(0))
      assert.is_true(tween:done(0))
    end)

    it('accepts an easing function', function()
      local tween = motion.Tween({
        from = 0,
        to = 1,
        ms = 10,
        ease = function()
          return 0.5
        end,
      })

      eq(0.5, tween:at(3))
    end)
  end)
end)

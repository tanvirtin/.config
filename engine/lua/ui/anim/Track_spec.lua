local Track = require('ui.anim.Track')
local motion = require('ui.motion')

local eq = assert.are.same

describe('ui.anim.Track:', function()
  it('holds the first value before it starts and the last after it ends', function()
    local track = Track.new({ { 100, 10 }, { 300, 50 } })

    eq(10, track:at(0))
    eq(50, track:at(900))
    eq(300, track:duration())
  end)

  it('moves linearly between keyframes unless the destination names an ease', function()
    eq(30, Track.new({ { 0, 10 }, { 200, 50 } }):at(100))

    local eased = Track.new({ { 0, 0 }, { 100, 100, 'in_cubic' } })

    assert.is_true(eased:at(50) < 20)
    eq(motion.ease.in_cubic(0.5) * 100, eased:at(50))
  end)

  it('takes keyframes in any order, and loops when asked', function()
    local track = Track.new({ { 200, 0 }, { 0, 100 } }, { loop = true })

    eq(100, track:at(0))
    eq(50, track:at(100))
    eq(50, track:at(300))
  end)

  it('refuses a broken track, naming the eases it knows', function()
    local ok, err = pcall(Track.new, {})
    eq(false, ok)
    eq('a track needs at least one keyframe', err)

    ok, err = pcall(Track.new, { { 0, 1, 'wobble' } })
    eq(false, ok)
    assert.is_truthy(err:find('unknown ease wobble (', 1, true))
    assert.is_truthy(err:find('out_bounce', 1, true))

    ok, err = pcall(Track.new, { { 'a', 1 } })
    eq(false, ok)
    assert.is_truthy(err:find('a keyframe is [ms, value]', 1, true))
  end)

  it('has easings that start at 0 and end at 1', function()
    for name, ease in pairs(motion.ease) do
      assert.is_true(math.abs(ease(0)) < 1e-9, name)
      assert.is_true(math.abs(ease(1) - 1) < 1e-9, name)
    end
  end)
end)

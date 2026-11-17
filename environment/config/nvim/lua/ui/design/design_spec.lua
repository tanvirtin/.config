local design = require('ui.design')

local eq = assert.are.same

describe('ui.design:', function()
  it('orders its layers from the gutter up to animation, every one with a rising priority', function()
    local last = -1

    for _, name in ipairs(design.layer.ORDER) do
      local priority = design.layer.of(name)

      assert.is_true(priority > last, name)
      last = priority
    end

    eq(vim.tbl_count(design.layer.PRIORITY), #design.layer.ORDER)
    eq(design.layer.of('effect') + 1, design.layer.above('effect'))
  end)

  it('refuses a layer or a static preset it does not know', function()
    assert.has_error(function()
      design.layer.of('nope')
    end)
    assert.has_error(function()
      design.static.density('nope')
    end)
  end)

  it('grows its static presets from a whisper to heavy, and fades a preset by a factor', function()
    local last = 0

    for _, name in ipairs(design.static.ORDER) do
      assert.is_true(design.static.density(name) > last, name)
      last = design.static.density(name)
    end

    eq(design.static.DENSITY.heavy / 2, design.static.density('heavy', 0.5))
  end)

  it('keeps one duration scale, rising from instant to deliberate', function()
    local scale = design.motion.DURATION

    assert.is_true(scale.instant < scale.fast)
    assert.is_true(scale.fast < scale.moderate)
    assert.is_true(scale.moderate < scale.slow)
    assert.is_true(scale.slow < scale.deliberate)
  end)

  it('seeds transient static per frame and ambient static per step', function()
    eq(3, design.static.seed(100))
    eq(1, design.static.seed(100, true))
  end)
end)

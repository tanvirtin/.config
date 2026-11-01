local tone = require('ui.tone')

local eq = assert.are.same

describe('ui.tone:', function()
  it('names the groups a tone is drawn with', function()
    eq('UiSurfaceWarn', tone.surface(tone.WARN))
    eq('UiRailError', tone.rail(tone.ERROR))
    eq('UiFlashAccent3', tone.flash(tone.ACCENT, 3))
    eq('UiPulseInfo12', tone.pulse(tone.INFO, 12))
  end)

  it('pulses in the text colour when it has no tone', function()
    eq('UiPulse4', tone.pulse(nil, 4))
  end)

  it('refuses a tone it does not know, instead of naming a group that does not exist', function()
    assert.has_error(function()
      tone.surface('Warning')
    end)
    assert.has_error(function()
      tone.pulse('warn', 1)
    end)
  end)

  it('has a source role for every tone', function()
    for _, name in ipairs(tone.ALL) do
      assert.is_string(tone.SOURCE[name])
    end
  end)
end)

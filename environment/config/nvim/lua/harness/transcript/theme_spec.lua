local theme = require('harness.transcript.theme')

local eq = assert.are.same

describe('harness.transcript.theme:', function()
  it('formats durations from a second up, in minutes past one', function()
    assert.is_nil(theme.duration(nil))
    assert.is_nil(theme.duration(999))
    eq('4s', theme.duration(4200))
    eq('2m 5s', theme.duration(125000))
  end)

  it('cycles motion frames and pulses the working label', function()
    eq('thinking.', theme.motion('thinking', 0))
    eq('thinking..', theme.motion('thinking', 300))
    eq('⠋', theme.motion('loading', 0))
    eq('⠙', theme.motion('loading', 100))
    local word, word_hl = theme.working_word(0, 0)
    local next_word, next_hl = theme.working_word(3000, 0)

    eq({ 'working', 'UiWorking1' }, { word, word_hl })
    eq({ 'pondering', 'UiWorking2' }, { next_word, next_hl })
    eq('working', theme.working_word(5000, 5000))
    eq('UiPulse1', theme.pulse(0))
    eq('UiPulse2', theme.pulse(300))
  end)

  it('pluralises counts', function()
    eq('1 tool', theme.plural(1, 'tool'))
    eq('3 tools', theme.plural(3, 'tool'))
  end)
end)

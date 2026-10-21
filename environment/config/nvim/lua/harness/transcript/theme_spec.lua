local theme = require('harness.transcript.theme')

local eq = assert.are.same

describe('harness.transcript.theme:', function()
  it('formats durations from a second up, in minutes past one', function()
    assert.is_nil(theme.duration(nil))
    assert.is_nil(theme.duration(999))
    eq('4s', theme.duration(4200))
    eq('2m 5s', theme.duration(125000))
  end)

  it('cycles spinner frames', function()
    eq(theme.SPINNER[1], theme.spinner(1))
    eq(theme.SPINNER[1], theme.spinner(#theme.SPINNER + 1))
    eq(theme.SPINNER[1], theme.spinner(nil))
  end)

  it('pluralises counts', function()
    eq('1 tool', theme.plural(1, 'tool'))
    eq('3 tools', theme.plural(3, 'tool'))
  end)
end)

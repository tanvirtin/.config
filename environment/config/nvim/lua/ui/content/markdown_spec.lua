local content = require('harness.transcript.content')
local hit_test = require('harness.ui.hit_test')
local builtin = require('harness.transcript.content.builtin')

require('ui.content.markdown')

local eq = assert.are.same

describe('ui.content.markdown:', function()
  before_each(function()
    content.reset()
    builtin()
  end)

  after_each(function()
    content.reset()
    builtin()
  end)

  it('should return the table cell under the cursor', function()
    local block = {
      kind = 'message',
      start = 0,
      lines = { '| a | b |', '| --- | --- |', '| 1 | 2 |' },
    }

    eq({ text = '1', kind = 'cell' }, hit_test.at(block, 2, 2))
    eq({ text = '2', kind = 'cell' }, hit_test.at(block, 2, 6))
  end)

  it('should return nil outside a table cell', function()
    assert.is_nil(hit_test.at({ kind = 'message', start = 0, lines = { 'hello' } }, 0, 1))
  end)
end)

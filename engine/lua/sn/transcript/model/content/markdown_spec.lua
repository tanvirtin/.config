local content = require('sn.transcript.model.content')
local hit_test = require('sn.transcript.model.content.hit_test')
local builtin = require('sn.transcript.model.content.builtin')

require('sn.transcript.model.content.markdown')

local eq = assert.are.same

describe('sn.transcript.model.content.markdown:', function()
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

local content = require('harness.transcript.content')
local hit_test = require('harness.ui.hit_test')
local builtin = require('harness.transcript.content.builtin')

local eq = assert.are.same

describe('harness.ui.hit_test:', function()
  before_each(function()
    content.reset()
    builtin()
  end)

  after_each(function()
    content.reset()
    builtin()
  end)

  it('should resolve a handler by content type', function()
    content.register({
      id = 'custom',
      kind = 'custom',
      render = { mode = 'raw' },
      hit_test = 'custom',
    })

    hit_test.bind('custom', function(block, row, col)
      return { text = 'ok', row = row, col = col }
    end)

    eq({ text = 'ok', row = 2, col = 3 }, hit_test.at({ kind = 'custom' }, 2, 3))
  end)

  it('should return nil for a type without a hit test', function()
    assert.is_nil(hit_test.at({ kind = 'message' }, 0, 0))
  end)
end)

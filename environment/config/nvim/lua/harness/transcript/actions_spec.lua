local Block = require('harness.transcript.Block')
local actions = require('harness.transcript.actions')
local content = require('harness.transcript.content')
local builtin = require('harness.transcript.content.builtin')

local eq = assert.are.same

describe('harness.transcript.actions:', function()
  before_each(function()
    content.reset()
    builtin()
  end)

  after_each(function()
    content.reset()
    builtin()
  end)

  it('should find the built-in diff action', function()
    local action = actions.find(Block.make(Block.KIND.diff, { 'x' }), 'diff')

    assert.is_not_nil(action)
    eq('diff', action.key)
  end)

  it('should run an action and return its result', function()
    local called = false

    content.register({
      id = 'custom',
      kind = 'custom',
      render = { mode = 'raw' },
      actions = {
        {
          key = 'go',
          handler = function()
            called = true
            return 'ok'
          end,
        },
      },
    })

    local handled, result = actions.run({}, { kind = 'custom' }, 'go')

    eq(true, handled)
    eq('ok', result)
    eq(true, called)
  end)

  it('should run a bound handler when the type declares only a key', function()
    content.register({
      id = 'symbolic',
      kind = 'symbolic',
      render = { mode = 'raw' },
      actions = { { key = 'symbolic-go' } },
    })

    actions.bind('symbolic-go', function()
      return 'bound'
    end)

    local handled, result = actions.run({}, { kind = 'symbolic' }, 'symbolic-go')

    eq(true, handled)
    eq('bound', result)
  end)

  it('should respect when and fall back', function()
    content.register({
      id = 'custom',
      kind = 'custom',
      render = { mode = 'raw' },
      actions = {
        {
          key = 'go',
          when = function()
            return false
          end,
          handler = function() end,
        },
      },
    })

    eq(nil, actions.find({ kind = 'custom' }, 'go'))
    assert.is_false(actions.run({}, { kind = 'custom' }, 'go'))
  end)

  it('should return nil without a block', function()
    eq(nil, actions.find(nil, 'diff'))
    assert.is_false(actions.run({}, nil, 'diff'))
  end)
end)

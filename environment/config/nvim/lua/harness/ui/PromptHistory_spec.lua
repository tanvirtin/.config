local PromptHistory = require('harness.ui.PromptHistory')
local events = require('harness.types.events')

local eq = assert.are.same

describe('harness.ui.PromptHistory:', function()
  it('lists the prompts of a session oldest first, once each', function()
    local session = {
      history = {
        events.prompt('one'),
        events.prompt('two'),
        events.prompt('steer', { steered = true }),
        events.prompt('one'),
        events.prompt('  '),
      },
    }

    eq({ 'two', 'one' }, PromptHistory.collect(session))
  end)

  it('puts prompts sent elsewhere before the session\'s own', function()
    local session = { history = { events.prompt('mine') } }

    eq({ 'other', 'mine' }, PromptHistory.collect(session, { 'other', 'mine' }))
  end)

  it('walks back and forth, giving the draft back at the end', function()
    local history = PromptHistory({ 'a', 'b', 'c' })

    eq('c', history:older('draft'))
    eq('b', history:older('ignored'))
    eq('a', history:older())
    assert.is_nil(history:older())
    eq('b', history:newer())
    eq('c', history:newer())
    eq('draft', history:newer())
    eq(false, history:browsing())
    assert.is_nil(history:newer())
  end)

  it('has nothing to recall when empty', function()
    assert.is_nil(PromptHistory({}):older('x'))
  end)
end)

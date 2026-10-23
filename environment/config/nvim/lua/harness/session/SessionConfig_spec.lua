local SessionConfig = require('harness.session.SessionConfig')
local events = require('harness.types.events')
local fake = require('harness.session.fake_session')

local eq = assert.are.same

describe('harness.session.SessionConfig:', function()
  local OPTIONS = {
    { id = 'mode', category = 'mode', currentValue = 'plan', options = { { value = 'plan', name = 'Plan' } } },
    {
      id = 'model',
      category = 'model',
      currentValue = 'opus',
      options = { { name = 'Claude', options = { { value = 'opus', name = 'Opus' } } } },
    },
  }

  it('flattens grouped choices and finds options by id or category', function()
    local session = fake.session()
    local config = SessionConfig(session)

    config:configure({ configOptions = vim.deepcopy(OPTIONS) })

    eq({ { value = 'opus', name = 'Opus' } }, SessionConfig.choices(OPTIONS[2]))
    eq('Opus', config:choice('model').name)
    eq('model', config:option('model').id)
    eq({ id = 'plan', name = 'Plan' }, config:mode())
    eq({ events.NOTICE.config }, session.notified)
  end)

  it('applies option, mode and command updates to the session', function()
    local session = fake.session()
    local config = SessionConfig(session)

    config:apply(events.new({ kind = events.KIND.config, options = vim.deepcopy(OPTIONS) }))
    config:apply(events.new({ kind = events.KIND.mode, id = 'code' }))
    config:apply(events.new({ kind = events.KIND.commands, commands = { { name = 'review' } } }))

    eq('code', session.options[1].currentValue)
    eq('review', session.commands[1].name)
  end)

  it('falls back to the agent\'s modes when it has no options', function()
    local session = fake.session()
    local config = SessionConfig(session)

    config:configure({ modes = { currentModeId = 'ask', availableModes = { { id = 'ask', name = 'Ask' } } } })

    eq({ id = 'ask', name = 'Ask' }, config:mode())
    eq({ { id = 'ask', name = 'Ask' } }, config:mode_choices())
  end)
end)

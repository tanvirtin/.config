local SessionConfig = require('harness.session.SessionConfig')
local config = require('harness.types.config')
local events = require('harness.types.events')
local fake = require('harness.session.fake_session')

local eq = assert.are.same

describe('harness.session.SessionConfig:', function()
  local function options()
    return {
      config.Option({
        id = 'mode',
        category = 'mode',
        current = 'plan',
        choices = { config.Choice({ value = 'plan', name = 'Plan' }), config.Choice({ value = 'code', name = 'Code' }) },
      }),
      config.Option({
        id = 'model',
        category = 'model',
        current = 'opus',
        choices = { config.Choice({ value = 'opus', name = 'Opus' }) },
      }),
    }
  end

  it('finds options by id or category, and the mode and model chosen in them', function()
    local session = fake.session()
    local settings = SessionConfig(session)

    settings:configure(options())

    eq('Opus', settings:choice('model').name)
    eq('model', settings:option('model').id)
    eq({ id = 'plan', name = 'Plan' }, settings:mode())
    eq({ { id = 'plan', name = 'Plan' }, { id = 'code', name = 'Code' } }, settings:mode_choices())
    eq({ events.NOTICE.config }, session.notified)
  end)

  it('applies option, mode and command updates to the session', function()
    local session = fake.session()
    local settings = SessionConfig(session)

    settings:apply(events.new({ kind = events.KIND.config, options = options() }))
    settings:apply(events.new({ kind = events.KIND.mode, id = 'code' }))
    settings:apply(events.new({ kind = events.KIND.commands, commands = { { name = 'review' } } }))

    eq('code', session.options[1].current)
    eq('review', session.commands[1].name)
  end)

  it('ignores an empty set of options, and has no mode without a mode option', function()
    local session = fake.session()
    local settings = SessionConfig(session)

    settings:configure({})

    eq({}, session.options)
    eq(nil, settings:mode())
    eq({}, settings:mode_choices())
    eq(nil, settings:set_mode('code'))
  end)
end)

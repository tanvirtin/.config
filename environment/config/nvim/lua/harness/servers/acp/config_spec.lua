local acp_config = require('harness.servers.acp.config')

local eq = assert.are.same

describe('harness.servers.acp.config:', function()
  it('reads config options, flattening grouped choices', function()
    local options = acp_config.options({
      {
        id = 'model',
        category = 'model',
        type = 'select',
        currentValue = 'opus',
        options = { { group = 'g', name = 'Claude', options = { { value = 'opus', name = 'Opus' } } } },
      },
    })

    eq({ { value = 'opus', name = 'Opus' } }, options[1].choices)
    eq(
      { 'model', 'model', 'select', 'opus' },
      { options[1].id, options[1].category, options[1].kind, options[1].current }
    )
  end)

  it('turns modes into a mode option of its own, only when no option is the mode', function()
    local modes = { currentModeId = 'ask', availableModes = { { id = 'ask', name = 'Ask' } } }
    local options = acp_config.options(nil, modes)

    eq({ acp_config.MODES, 'mode', 'ask' }, { options[1].id, options[1].category, options[1].current })
    eq(1, #acp_config.options({ { id = 'mode', category = 'mode', currentValue = 'x' } }, modes))
  end)

  it('reads a session the agent opened and the sessions it stores', function()
    local opened = acp_config.opened({ sessionId = 's1', configOptions = { { id = 'model', currentValue = 'opus' } } })

    eq({ 's1', 'model' }, { opened.id, opened.options[1].id })
    eq(
      { id = 's1', title = 'one', updated_at = 'now' },
      acp_config.stored({ sessionId = 's1', title = 'one', updatedAt = 'now' })
    )
  end)
end)

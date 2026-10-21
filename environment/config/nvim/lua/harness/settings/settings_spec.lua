local settings = require('harness.settings')

local eq = assert.are.same

describe('harness.settings:', function()
  local saved

  before_each(function()
    saved = {}

    for _, name in ipairs(settings.NAMES) do
      saved[name] = vim.deepcopy(settings[name].data)
    end
  end)

  after_each(function()
    for _, name in ipairs(settings.NAMES) do
      settings[name].data = saved[name]
    end
  end)

  it('merges per-feature tables and hands back the rest', function()
    local rest = settings.assign({
      transcript = { tick_ms = 50 },
      keymaps = { transcript = { yank = 'Y' } },
      max_running = 2,
    })

    eq(50, settings.transcript:get('tick_ms'))
    eq('Y', settings.keymaps:get('transcript').yank)
    eq('gf', settings.keymaps:get('transcript').open)
    eq({ max_running = 2 }, rest)
  end)

  it('applies theme overrides to the transcript theme at once', function()
    local theme = require('harness.transcript.theme')

    settings.assign({ theme = { user_icon = 'U ' } })

    eq('U ', theme.USER_ICON)
  end)

  it('reads every default without error', function()
    for _, name in ipairs(settings.NAMES) do
      settings[name]:for_each(function(key)
        assert.is_not_nil(settings[name]:get(key))
      end)
    end
  end)
end)

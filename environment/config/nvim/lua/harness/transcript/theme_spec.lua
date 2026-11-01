local theme = require('harness.transcript.theme')

local eq = assert.are.same

describe('harness.transcript.theme:', function()
  it('formats durations from a second up, in minutes past one', function()
    assert.is_nil(theme.duration(nil))
    assert.is_nil(theme.duration(999))
    eq('4s', theme.duration(4200))
    eq('2m 5s', theme.duration(125000))
  end)

  it('cycles motion frames and pulses the working label', function()
    eq('thinking.', theme.motion('thinking', 0))
    eq('thinking..', theme.motion('thinking', 300))
    eq('⠋', theme.motion('loading', 0))
    eq('⠙', theme.motion('loading', 100))
    local word, word_hl = theme.working_word(0, 0)
    local next_word, next_hl = theme.working_word(3000, 0)

    eq({ 'working', 'UiWorking1' }, { word, word_hl })
    eq({ 'pondering', 'UiWorking2' }, { next_word, next_hl })
    eq('working', theme.working_word(5000, 5000))
    eq('UiPulse1', theme.pulse(0))
    eq('UiPulse2', theme.pulse(100))
  end)

  describe('reduced motion', function()
    local settings = require('harness.settings.theme')

    before_each(function()
      settings:assign({ motion = vim.tbl_extend('force', settings:get('motion'), { reduced = true }) })
    end)

    after_each(function()
      settings:assign({ motion = vim.tbl_extend('force', settings:get('motion'), { reduced = false }) })
    end)

    it('holds the spinner and the pulse still', function()
      eq(theme.RUNNING_ICON, theme.spinner(0))
      eq(theme.RUNNING_ICON, theme.spinner(5000))
      eq('UiPulse1', theme.pulse(700))
      eq('UiPulseWarn1', theme.pulse(700, 'Warn'))
    end)

    it('never flashes a finished tool', function()
      local Flashes = require('harness.ui.Flashes')
      local flashes = Flashes(require('core.Buffer')():create(false, true))

      eq(false, flashes:scan({ { kind = 'tool', id = 't', start = 0, finished = 1000, status = 'completed' } }, 1000))
    end)

    it('shows a toast at full strength at once, with no timer left running once it is gone', function()
      local Toast = require('harness.ui.Toast')
      local window = Toast.show('hi')

      eq(12, window:get_option('winblend'))
      Toast.dismiss()
    end)
  end)

  it('pluralises counts', function()
    eq('1 tool', theme.plural(1, 'tool'))
    eq('3 tools', theme.plural(3, 'tool'))
  end)
end)

local Tile = require('ui.pixel.Tile')
local graphics = require('core.graphics')
local ticker = require('ui.pixel.ticker')
local theme = require('harness.transcript.theme')
local settings = require('harness.settings.theme')

local eq = assert.are.same

describe('harness.transcript.theme:', function()
  it('formats durations from a second up, in minutes past one', function()
    assert.is_nil(theme.duration(nil))
    assert.is_nil(theme.duration(999))
    eq('4s', theme.duration(4200))
    eq('2m 5s', theme.duration(125000))
  end)

  it('keeps every motion on one beat: twelve pulse steps', function()
    eq(1200, theme.beat())
    eq('UiPulse1', theme.pulse(0))
    eq('UiPulse2', theme.pulse(100))
    eq('UiPulse1', theme.pulse(1200))
  end)

  it('strikes once a beat: the hammer flares and settles while its spark flies and cools', function()
    local icon = require('harness.settings.theme'):get('motion').working.icon

    eq({ { icon, 'UiStrike1' }, { '✦', 'UiSpark1' } }, theme.working(0))
    eq({ { icon, 'UiStrike2' }, { '•', 'UiSpark2' } }, theme.working(100))
    eq({ { icon, 'UiStrike3' }, { '·', 'UiSpark3' } }, theme.working(200))
    eq({ { icon, 'UiStrike4' }, { ' ', 'UiSpark3' } }, theme.working(300))
    eq('✦', theme.working(1200)[2][1])
    eq(icon .. ' ', theme.working_text(600))
  end)

  it('lands a heavy blow as the word changes and lighter taps on the beats between', function()
    local icon = require('harness.settings.theme'):get('motion').working.icon

    eq({ { icon, 'UiStrike1' }, { '✦', 'UiSpark1' } }, theme.working(0, 0))
    eq({ { icon, 'UiStrike3' }, { '•', 'UiSpark2' } }, theme.working(1200, 0))
    eq({ { icon, 'UiStrike4' }, { '·', 'UiSpark3' } }, theme.working(2500, 0))
    eq({ { icon, 'UiStrike1' }, { '✦', 'UiSpark1' } }, theme.working(3600, 0))
  end)

  it(
    'turns the winbar badge through its facets once a beat, brightest at the top of the pulse and dimmest at the trough',
    function()
      eq({ '◆ ', 'UiPulse1' }, theme.badge(0))
      eq({ '◈ ', 'UiPulse3' }, theme.badge(200))
      eq({ '· ', 'UiPulse7' }, theme.badge(600))
      eq({ '◈ ', 'UiPulse11' }, theme.badge(1000))
      eq({ '◆ ', 'UiPulse1' }, theme.badge(1200))
    end
  )

  it('changes the working word on a spark, every third beat of the turn', function()
    local words = require('harness.settings.theme'):get('motion').working.words

    eq({ words[1], 'UiWorking1' }, { theme.working_word(0, 0) })
    eq(words[1], theme.working_word(3599, 0))
    eq({ words[2], 'UiWorking2' }, { theme.working_word(3600, 0) })
    eq(words[1], theme.working_word(5000, 5000))
  end)

  describe('reduced motion', function()
    local settings = require('harness.settings.theme')

    before_each(function()
      settings:assign({ motion = vim.tbl_extend('force', settings:get('motion'), { reduced = true }) })
    end)

    after_each(function()
      settings:assign({ motion = vim.tbl_extend('force', settings:get('motion'), { reduced = false }) })
    end)

    it('holds the hammer, its spark and the pulse still', function()
      local icon = settings:get('motion').working.icon

      eq({ { icon, 'UiPulse1' }, { ' ', 'UiSpark1' } }, theme.working(0))
      eq(theme.TOOL_ICONS.in_progress, theme.spinner(500))
      eq({ '◆ ', 'UiPulse1' }, theme.badge(600))
      eq('▰', theme.sweep(900)[1][1])
      eq({ { 'kindling', 'UiWorking1' } }, theme.forged('kindling', 'UiWorking1', 0, 0))
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

  it('forges each word over its beats: fault lines telegraph the break, the taps hammer the letters out', function()
    local working = require('harness.settings.theme'):get('motion').working
    local crack, ingot = working.crack, working.ingot

    eq({
      { crack:rep(2), 'UiIngot2' },
      { ingot, 'UiIngot1' },
      { crack, 'UiIngot2' },
      { ingot, 'UiIngot1' },
      { crack:rep(2), 'UiIngot2' },
      { ingot, 'UiIngot1' },
    }, theme.forged('kindling', 'UiWorking1', 0, 0))
    eq({
      { crack:rep(2), 'UiIngot2' },
      { ingot, 'UiIngot4' },
      { crack, 'UiIngot2' },
      { ingot, 'UiIngot4' },
      { crack:rep(2), 'UiIngot2' },
      { ingot, 'UiIngot4' },
    }, theme.forged('kindling', 'UiWorking1', 1100, 0))
    eq({
      { 'ki', 'UiWorking1' },
      { crack, 'UiIngot2' },
      { 'd', 'UiWorking1' },
      { crack, 'UiIngot2' },
      { 'in', 'UiWorking1' },
      { crack, 'UiIngot2' },
    }, theme.forged('kindling', 'UiWorking1', 1800, 0))
    eq({ { 'kindling', 'UiWorking1' } }, theme.forged('kindling', 'UiWorking1', 3000, 0))
    eq({ { 'kindling', 'UiWorking1' } }, theme.forged('kindling', 'UiWorking1', 600))
    eq({ { 'Thinking', 'UiPulse1' } }, theme.forged('Thinking', 'UiPulse1', 0, 0))
  end)

  it('flashes each batch bright on the beat it breaks, cooling to the word within three pulse steps', function()
    eq({
      { 'ki', 'UiWorking1' },
      { 'n', 'UiWorkingGlint1_1' },
      { 'd', 'UiWorking1' },
      { 'l', 'UiWorkingGlint1_1' },
      { 'in', 'UiWorking1' },
      { 'g', 'UiWorkingGlint1_1' },
    }, theme.forged('kindling', 'UiWorking1', 2400, 0))
    eq({
      { 'ki', 'UiWorking1' },
      { 'n', 'UiWorkingGlint1_2' },
      { 'd', 'UiWorking1' },
      { 'l', 'UiWorkingGlint1_2' },
      { 'in', 'UiWorking1' },
      { 'g', 'UiWorkingGlint1_2' },
    }, theme.forged('kindling', 'UiWorking1', 2500, 0))
    eq({ { 'kindling', 'UiWorking1' } }, theme.forged('kindling', 'UiWorking1', 2700, 0))
  end)

  it('spins a running tool a frame per pulse step, and sweeps a loading session once a beat', function()
    local frames = require('harness.settings.theme'):get('motion').tool.frames

    eq({ frames[1] .. ' ', 'UiAccent' }, theme.spinner(0))
    eq({ frames[2] .. ' ', 'UiAccent' }, theme.spinner(120))
    eq({ frames[1] .. ' ', 'UiAccent' }, theme.spinner(#frames * 100))
    eq({ frames[1] .. ' ', 'UiAccent' }, theme.spinner(1200))
    eq({ { '▰', 'UiAccent' }, { '▱', 'UiMuted' }, { '▱', 'UiMuted' }, { '▱', 'UiMuted' } }, theme.sweep(0))
    eq('▰', theme.sweep(900)[4][1])
  end)

  it('sweeps a loading session as one pixel bar as wide as the loading width, when there are pixels', function()
    local original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }

    Tile.available = function()
      return true
    end
    graphics.upload = function() end
    graphics.delete = function() end

    local chunks = theme.sweep(0)
    local width = vim.fn.strdisplaywidth(chunks[1][1])

    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete

    eq(1, #chunks)
    eq(settings:get('motion').loading.width, width)
  end)

  it('pluralises counts', function()
    eq('1 tool', theme.plural(1, 'tool'))
    eq('3 tools', theme.plural(3, 'tool'))
  end)
end)

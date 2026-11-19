local text = require('core.text')
local Tile = require('ui.pixel.Tile')
local graphics = require('core.editor.graphics')
local ticker = require('ui.pixel.ticker')
local indicators = require('ui.pixel.indicators')
local theme = require('sn.transcript.theme')
local mascot = require('sn.transcript.mascot')

local eq = assert.are.same

describe('sn.transcript.theme:', function()
  it('formats durations from a second up, in minutes past one', function()
    assert.is_nil(theme.duration(nil))
    assert.is_nil(theme.duration(999))
    eq('4s', theme.duration(4200))
    eq('2m 5s', theme.duration(125000))
  end)

  it('keeps the working words on one beat: twelve pulse steps', function()
    eq(require('ui.design.motion').DURATION.deliberate, theme.beat())
  end)

  describe('without pixels', function()
    local available

    before_each(function()
      available = Tile.available
      Tile.available = function()
        return false
      end
    end)

    after_each(function()
      Tile.available = available
    end)

    it('cycles the busy loader a glyph per step, in the accent, two cells wide', function()
      eq({ '⠋ ', 'UiAccent' }, theme.loader('busy', 0))
      eq({ '⠙ ', 'UiAccent' }, theme.loader('busy', 100))
      eq({ '⠋ ', 'UiAccent' }, theme.loader('busy', 600))
    end)

    it('gives each kind of loader its own glyphs and group', function()
      eq({ '⠢ ', 'UiThought' }, theme.loader('thinking', 0))
      eq({ '⠉ ', 'UiWarn' }, theme.loader('waiting', 0))
      eq({ '⡇ ', 'UiAccent' }, theme.loader('loading', 0))
      eq({ '· ', 'UiMuted' }, theme.loader('idle', 0))
    end)

    it('shows the busy glyph on the working line and in the working text', function()
      eq({ { '⠋', 'UiAccent' } }, theme.working(0))
      eq({ { '⠙', 'UiAccent' } }, theme.working(100))
      eq({ { '⠉', 'UiWarn' } }, theme.working(0, nil, 'wait'))
      eq('⠙', theme.working_text(700))
    end)
  end)

  describe('with pixels', function()
    local original

    before_each(function()
      original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
      Tile.available = function()
        return true
      end
      graphics.upload = function() end
      graphics.delete = function() end
    end)

    after_each(function()
      indicators.stop()
      ticker.stop()
      Tile.drain()
      Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
    end)

    it('draws each loader as the pixel chunk of its kind', function()
      eq(indicators.chunk('busy'), theme.loader('busy', 0))
      eq(indicators.chunk('loading'), theme.loader('loading', 900))
      eq(indicators.chunk('waiting'), theme.loader('waiting', 0))
    end)
  end)

  describe('reduced motion', function()
    local settings = require('sn.settings.theme')

    before_each(function()
      settings:assign({ motion = vim.tbl_extend('force', settings:get('motion'), { reduced = true }) })
    end)

    after_each(function()
      settings:assign({ motion = vim.tbl_extend('force', settings:get('motion'), { reduced = false }) })
    end)

    it('holds the loaders and the working line still, whatever the time', function()
      eq({ { '⠋', 'UiAccent' } }, theme.working(0))
      eq({ '⠋ ', 'UiAccent' }, theme.loader('busy', 500))
      eq({ '⠋ ', 'UiAccent' }, theme.loader('busy', 9000))
      eq({ '⡇ ', 'UiAccent' }, theme.loader('loading', 900))
    end)

    it('never flashes a finished tool', function()
      local Flashes = require('sn.transcript.effects.Flashes')
      local flashes = Flashes(require('core.editor.Buffer')():create(false, true))

      eq(false, flashes:scan({ { kind = 'tool', id = 't', start = 0, finished = 1000, status = 'completed' } }, 1000))
    end)

    it('shows a toast at full strength at once, with no timer left running once it is gone', function()
      local Toast = require('sn.ui.Toast')
      local window = Toast.show('hi')

      eq(12, window:get_option('winblend'))
      Toast.dismiss()
    end)
  end)

  it('draws the working line as one pixel mascot three cells wide, when there are pixels', function()
    local original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }

    Tile.available = function()
      return true
    end
    graphics.upload = function() end
    graphics.delete = function() end

    local chunks = theme.working(0, 0)
    local width = vim.fn.strdisplaywidth(chunks[1][1])

    mascot.stop()
    ticker.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete

    eq(1, #chunks)
    eq(mascot.COLS, width)
  end)

  it('pluralises counts', function()
    eq('1 tool', theme.plural(1, 'tool'))
    eq('3 tools', theme.plural(3, 'tool'))
  end)
end)

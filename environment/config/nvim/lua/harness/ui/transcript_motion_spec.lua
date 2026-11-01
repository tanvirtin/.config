local Animator = require('harness.ui.Animator')
local transcript_motion = require('harness.ui.transcript_motion')

local eq = assert.are.same

describe('harness.ui.transcript_motion:', function()
  local view

  before_each(function()
    view = {
      animator = Animator(),
      buffer = {
        is_valid = function()
          return true
        end,
      },
    }
  end)

  after_each(function()
    view.animator:close()
    transcript_motion.unregister('test')
  end)

  local function ids()
    return vim.tbl_map(function(effect)
      return effect.id
    end, transcript_motion.effects())
  end

  it('ships the collapse of an answered card, the fade of new rows and the flash of a finished tool', function()
    eq({ 'collapse', 'fade', 'flash' }, ids())
  end)

  it('gives each view its own instance of every effect', function()
    local other = { animator = Animator(), buffer = view.buffer }

    transcript_motion.attach(view)
    transcript_motion.attach(other)

    assert.is_not.equal(view.effects.flash, other.effects.flash)
    local keys = vim.tbl_keys(view.effects)

    table.sort(keys)
    eq({ 'collapse', 'fade', 'flash' }, keys)
    other.animator:close()
  end)

  it('runs a registered effect on the view\'s animator when it asks to, and only then', function()
    local steps, ask = 0, false

    transcript_motion.register({
      id = 'test',
      create = function()
        return {
          observe = function()
            return ask
          end,
          step = function()
            steps = steps + 1

            return steps < 3
          end,
        }
      end,
    })
    view.effects = {}
    transcript_motion.attach(view)
    view.effects.collapse = {}
    view.effects.fade = {}
    view.effects.flash = {}

    transcript_motion.settle(view)
    eq(0, view.animator:count())

    ask = true
    transcript_motion.settle(view)
    eq(1, view.animator:count())

    view.animator:step(0)
    view.animator:step(0)
    view.animator:step(0)

    eq(3, steps)
    eq(0, view.animator:count())
  end)

  it('offers an effect the state before a write, and starts it when it says it began', function()
    local seen

    transcript_motion.register({
      id = 'test',
      create = function()
        return {
          before = function(_, state)
            seen = state

            return true
          end,
          step = function()
            return false
          end,
        }
      end,
    })
    transcript_motion.attach(view)
    view.effects.collapse = {}
    view.effects.fade = {}
    view.effects.flash = {}

    transcript_motion.before(view, { asks = {} })

    eq({ asks = {} }, seen)
    eq(1, view.animator:count())
  end)

  it('replaces an effect registered again under the same id', function()
    transcript_motion.register({ id = 'test', create = function() end })
    transcript_motion.register({ id = 'test', create = function() end })

    eq(4, #ids())
  end)
end)

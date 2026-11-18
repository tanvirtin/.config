local Timer = require('core.Timer')
local console = require('core.console')
local motion = require('ui.design.motion')
local ticker = require('ui.pixel.ticker')

local eq = assert.are.same

describe('ui.pixel.ticker:', function()
  local original_now, original_notify, reports

  before_each(function()
    original_now = Timer.now
    original_notify = console.notify_now
    reports = {}
    console.notify_now = function(message, level)
      reports[#reports + 1] = { message, level }
    end
  end)

  after_each(function()
    ticker.stop()
    Timer.now = original_now
    console.notify_now = original_notify
  end)

  it('ticks on the stepped clock', function()
    eq(motion.STEP_MS, ticker.STEP_MS)
  end)

  it('starts its timer when the first step is added and closes it with the last one', function()
    eq(false, ticker.running())

    ticker.add('a', function() end)
    ticker.add('b', function() end)
    eq(true, ticker.running())
    eq(2, ticker.count())

    ticker.remove('a')
    eq(true, ticker.running())

    ticker.remove('b')
    eq(false, ticker.running())
    eq(0, ticker.count())
  end)

  it('restarts its timer on the next add after it closed', function()
    ticker.add('a', function() end)
    ticker.remove('a')
    ticker.add('b', function() end)

    eq(true, ticker.running())
  end)

  it('replaces the step of a key that is added again', function()
    local calls = {}

    ticker.add('a', function()
      calls[#calls + 1] = 'first'
      return true
    end)
    ticker.add('a', function()
      calls[#calls + 1] = 'second'
      return true
    end)
    ticker.step(1)

    eq(1, ticker.count())
    eq({ 'second' }, calls)
  end)

  it('calls the steps in insertion order, with the given time', function()
    local calls = {}

    for _, key in ipairs({ 'c', 'a', 'b' }) do
      ticker.add(key, function(now)
        calls[#calls + 1] = { key, now }
      end)
    end
    ticker.step(42)

    eq({ { 'c', 42 }, { 'a', 42 }, { 'b', 42 } }, calls)
  end)

  it('removes a step that returns false or nothing, and keeps one that returns true', function()
    local calls = {}

    ticker.add('stop', function()
      return false
    end)
    ticker.add('quiet', function() end)
    ticker.add('keep', function()
      return true
    end)
    ticker.step(1)
    ticker.step(2)

    eq(1, ticker.count())
    eq(true, ticker.running())
    ticker.add('keep', function()
      calls[#calls + 1] = true
    end)
    ticker.step(3)
    eq({ true }, calls)
  end)

  it('removes a step that throws and keeps the others running', function()
    local calls = 0

    ticker.add('broken', function()
      error('boom')
    end)
    ticker.add('steady', function()
      calls = calls + 1
      return true
    end)
    ticker.step(1)
    ticker.step(2)

    eq(1, ticker.count())
    eq(2, calls)
  end)

  it('reports a step that throws once, as a warning, and then removes it', function()
    ticker.add('broken', function()
      error('boom', 0)
    end)

    ticker.step(1)
    ticker.step(2)

    eq({ { 'pixel animation stopped: boom', 'warn' } }, reports)
    eq(0, ticker.count())
  end)

  it('reports nothing for a step that returns false', function()
    ticker.add('stop', function()
      return false
    end)

    ticker.step(1)

    eq({}, reports)
    eq(0, ticker.count())
  end)

  it('lets a step remove another step, which then does not run that frame', function()
    local calls = {}

    ticker.add('first', function()
      calls[#calls + 1] = 'first'
      ticker.remove('second')
      return true
    end)
    ticker.add('second', function()
      calls[#calls + 1] = 'second'
      return true
    end)
    ticker.step(1)

    eq({ 'first' }, calls)
    eq(1, ticker.count())
  end)

  it('lets a step add a step that runs from the next frame on', function()
    local calls = {}

    ticker.add('spawner', function()
      calls[#calls + 1] = 'spawner'
      ticker.add('child', function()
        calls[#calls + 1] = 'child'
        return true
      end)
      return true
    end)
    ticker.step(1)
    eq({ 'spawner' }, calls)

    ticker.step(2)
    eq({ 'spawner', 'spawner', 'child' }, calls)
  end)

  it('does nothing to an unknown key', function()
    ticker.remove('missing')

    eq(0, ticker.count())
    eq(false, ticker.running())
  end)

  it('removes everything and closes the timer on stop', function()
    ticker.add('a', function() end)
    ticker.add('b', function() end)
    ticker.stop()

    eq(0, ticker.count())
    eq(false, ticker.running())
  end)

  it('runs its steps on the timer, with the clock', function()
    local seen = {}

    Timer.now = function()
      return 77
    end
    ticker.add('clock', function(now)
      seen[#seen + 1] = now
      return true
    end)

    vim.wait(500, function()
      return #seen >= 2
    end, 10)

    assert.is_true(#seen >= 2)
    eq(77, seen[1])
  end)
end)

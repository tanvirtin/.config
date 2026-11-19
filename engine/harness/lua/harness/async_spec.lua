local async = require('harness.async')

local eq = assert.are.same

describe('harness.async:', function()
  it('awaits an already completed future', function()
    local future = async.Future.new()
    future:set_result(42)

    local task = async.run(function()
      return async.await(future)
    end)

    eq(task:wait(), 42)
  end)

  it('chains a task into another task', function()
    local gate = async.Future.new()

    local inner = async.run(function()
      return async.await(gate)
    end)

    local outer = async.run(function()
      return async.await(inner)
    end)

    gate:set_result('done')

    eq(outer:wait(), 'done')
  end)

  it('hands an awaited failure back as a value, for the caller to forward', function()
    local boom = async.run(function()
      return nil, 'boom'
    end)

    local outer = async.run(function()
      local _, err = async.await(boom)

      return nil, 'outer: ' .. err
    end)

    eq({ nil, 'outer: boom' }, { outer:wait() })
  end)

  it('reports a task that fails, or raises, through wait', function()
    local failed = async.run(function()
      return nil, 'nope'
    end)
    local raised = async.run(function()
      error('broken', 0)
    end)

    eq({ nil, 'nope' }, { failed:wait() })
    eq({ nil, 'broken' }, { raised:wait() })
  end)

  it('keeps draining after a callback fails', function()
    local console = require('core.console')
    local notify = console.notify
    local errors, seen = {}, {}

    console.notify = function(message)
      errors[#errors + 1] = message
    end

    local ok, err = pcall(function()
      local future = async.Future.new()

      future:on_complete(function()
        error('boom', 0)
      end)
      future:on_complete(function()
        seen[#seen + 1] = 'after'
      end)
      future:set_result(1)
      async.drain()
    end)

    console.notify = notify

    if not ok then error(err, 0) end

    eq({ 'after' }, seen)
    assert.is_truthy(errors[1]:find('boom', 1, true))
  end)

  it('times out with an error value, not an error', function()
    eq({ nil, 'timed out waiting for a result' }, { async.Future():wait(10) })
  end)
end)

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

  it('propagates errors raised while awaiting', function()
    local boom = async.run(function()
      error('boom', 0)
    end)

    local outer = async.run(function()
      async.await(boom)
    end)

    local ok = pcall(function()
      outer:wait()
    end)

    eq(ok, false)
  end)

  it('reports task errors through wait', function()
    local task = async.run(function()
      error('nope', 0)
    end)

    local ok, err = pcall(function()
      task:wait()
    end)

    eq(ok, false)
    eq(err, 'nope')
  end)
end)

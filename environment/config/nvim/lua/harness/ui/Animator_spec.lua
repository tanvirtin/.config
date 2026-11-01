local Animator = require('harness.ui.Animator')

local eq = assert.are.same

describe('harness.ui.Animator:', function()
  local animator

  after_each(function()
    animator:close()
  end)

  it('runs nothing and holds no timer until an animation is added', function()
    animator = Animator()

    assert.is_false(animator:is_running())
    eq(0, animator:count())
  end)

  it('steps every animation with the time, and drops the ones that finish', function()
    animator = Animator()

    local kept, finished = {}, {}

    animator:add('kept', function(now)
      kept[#kept + 1] = now

      return true
    end)
    animator:add('finished', function(now)
      finished[#finished + 1] = now

      return false
    end)
    animator:step(10)
    animator:step(20)

    eq({ 10, 20 }, kept)
    eq({ 10 }, finished)
    eq(1, animator:count())
  end)

  it('stops its timer when the last animation finishes, and starts it again for the next', function()
    animator = Animator()

    animator:add('one', function()
      return false
    end)
    assert.is_true(animator:is_running())

    animator:step(0)

    assert.is_false(animator:is_running())

    animator:add('two', function()
      return true
    end)

    assert.is_true(animator:is_running())
  end)

  it('replaces an animation added under the same key', function()
    animator = Animator()

    local calls = {}

    animator:add('a', function()
      calls[#calls + 1] = 'old'

      return true
    end)
    animator:add('a', function()
      calls[#calls + 1] = 'new'

      return true
    end)
    animator:step(0)

    eq({ 'new' }, calls)
    eq(1, animator:count())
  end)

  it('lets an animation add or cancel others while stepping', function()
    animator = Animator()

    local ran = {}

    animator:add('first', function()
      ran[#ran + 1] = 'first'
      animator:cancel('second')

      return false
    end)
    animator:add('second', function()
      ran[#ran + 1] = 'second'

      return true
    end)
    animator:step(0)

    eq({ 'first' }, ran)
    eq(0, animator:count())
  end)

  it('ticks on its own timer until idle', function()
    animator = Animator()

    local calls = 0

    animator:add('a', function()
      calls = calls + 1

      return calls < 3
    end)

    vim.wait(500, function()
      return not animator:is_running()
    end)

    eq(3, calls)
    assert.is_false(animator:is_running())
  end)

  it('stops and reports when an animation errors', function()
    local failure

    animator = Animator(function(err)
      failure = err
    end)
    animator:add('bad', function()
      error('boom')
    end)

    vim.wait(500, function()
      return failure ~= nil
    end)

    assert.truthy(tostring(failure):find('boom', 1, true))
    assert.is_false(animator:is_running())
    eq(0, animator:count())
  end)
end)

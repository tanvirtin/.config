local Timer = require('core.Timer')

local eq = assert.are.same

describe('core.Timer:', function()
  it('runs a callback once after a delay', function()
    local calls = 0
    local timer = Timer():after(20, function()
      calls = calls + 1
    end)

    vim.wait(200, function()
      return calls > 0
    end)
    vim.wait(60)

    eq(1, calls)
    timer:close()
  end)

  it('repeats until stopped, and restarting replaces the pending run', function()
    local calls = 0
    local timer = Timer():every(10, function()
      calls = calls + 1
    end)

    vim.wait(200, function()
      return calls >= 3
    end)
    timer:stop()

    local stopped_at = calls

    vim.wait(60)
    eq(stopped_at, calls)
    eq(false, timer:is_active())

    local which

    timer:after(30, function()
      which = 'first'
    end)
    timer:after(30, function()
      which = 'second'
    end)
    vim.wait(200, function()
      return which ~= nil
    end)

    eq('second', which)
    timer:close()
  end)

  it('closes more than once without error, and can start again after closing', function()
    local timer = Timer()
    local ran = false

    timer:close()
    timer:close()
    timer:after(5, function()
      ran = true
    end)
    vim.wait(200, function()
      return ran
    end)

    eq(true, ran)
    timer:close()
  end)
end)

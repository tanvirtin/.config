local status = require('harness.ui.status')

local eq = assert.are.same

local function session(opts)
  return {
    running = function()
      return opts.running or false
    end,
    waiting = function()
      return opts.waiting or {}
    end,
    subagents = {
      summary = function()
        return { active = opts.agents or 0 }
      end,
    },
  }
end

describe('harness.ui.status:', function()
  it('should summarize running sessions, agents and waits', function()
    local list = {
      session({ running = true, agents = 2, waiting = { {} } }),
      session({ running = false, agents = 1 }),
    }

    eq({ running = 1, agents = 3, waiting = 1 }, status.summary(list))
    eq(true, status.visible(list))

    local text = status.text(list)

    assert.is_truthy(text:find('1 running', 1, true))
    assert.is_truthy(text:find('3 agents', 1, true))
    assert.is_truthy(text:find('waiting', 1, true))
  end)

  it('should be empty when nothing runs', function()
    eq({ running = 0, agents = 0, waiting = 0 }, status.summary({}))
    eq(false, status.visible({}))
    eq('', status.text({}))
  end)
end)

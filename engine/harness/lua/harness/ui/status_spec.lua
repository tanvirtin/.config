local status = require('harness.ui.status')

local eq = assert.are.same

local function session(opts)
  return {
    title = opts.title,
    key = opts.key,
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

  it('should name the session that waits, and count them when more than one does', function()
    local one = status.text({ session({ waiting = { {} }, title = 'shiny-toasting-scroll' }) })

    assert.is_truthy(one:find('waiting in shiny-toasting-scroll', 1, true))

    local two = status.text({
      session({ waiting = { {} }, title = 'first' }),
      session({ waiting = { {}, {} }, title = 'second' }),
    })

    assert.is_truthy(two:find('3 waiting', 1, true))
    assert.is_falsy(two:find('waiting in', 1, true))
  end)

  it('should list only the sessions holding a request', function()
    local idle = session({ title = 'idle' })
    local busy = session({ waiting = { {} }, title = 'busy' })

    eq({ busy }, status.waiting({ idle, busy }))
    eq({}, status.waiting({ idle }))
  end)

  it('should be empty when nothing runs', function()
    eq({ running = 0, agents = 0, waiting = 0 }, status.summary({}))
    eq(false, status.visible({}))
    eq('', status.text({}))
  end)
end)

local SessionHub = require('harness.SessionHub')

local eq = assert.are.same

local function store()
  return {
    each = function() end,
    on = function()
      return function() end
    end,
    EVENT = { event = 'event', close = 'close' },
    clear = function() end,
  }
end

describe('harness.SessionHub:', function()
  it('keeps its settings, keys and workspaces to itself', function()
    local a, b = SessionHub(store()), SessionHub(store())

    a:configure({ max_depth = 1, max_running = 9 })

    eq({ 1, 9 }, { a.config.max_depth, a.config.max_running })
    eq({ 2, 4 }, { b.config.max_depth, b.config.max_running })
    eq({ 'h1', 'h2', 'h1' }, { a:_new_key(), a:_new_key(), b:_new_key() })
    assert.are_not.equal(a:workspace('/x'), b:workspace('/x'))
    assert.are.equal(a:workspace('/x'), a:workspace('/x'))
  end)

  it('starts from the defaults without sharing them', function()
    local a = SessionHub(store())

    a.config.max_depth = 7

    eq(2, SessionHub(store()).config.max_depth)
    eq(2, SessionHub.DEFAULTS.max_depth)
  end)

  it('reads the running limit from its own settings', function()
    local hub = SessionHub(store())
    local idle = {
      running = function()
        return false
      end,
    }

    eq(true, hub:admit(idle))
    hub:configure({ max_running = 0 })
    eq(false, hub:admit(idle))
  end)
end)

local Admission = require('harness.Admission')

local eq = assert.are.same

local function fake_session(name, state, queued, since)
  local session = { name = name, drained = false }

  function session:running()
    return state == 'running'
  end

  function session:idle()
    return state == 'idle'
  end

  session.prompts = {
    size = function()
      return queued or 0
    end,
    since = function()
      return since or math.huge
    end,
    drain = function()
      session.drained = true
      state = 'running'
    end,
  }

  return session
end

local function fake_store(sessions)
  return {
    each = function(fn)
      for _, session in ipairs(sessions) do
        fn(session)
      end
    end,
    on = function()
      return function() end
    end,
    EVENT = { event = 'event', close = 'close' },
  }
end

local function admission(sessions, limit)
  return Admission({
    store = fake_store(sessions),
    limit = function()
      return limit
    end,
  })
end

describe('harness.Admission:', function()
  it('counts the sessions with a turn running', function()
    local a = admission({ fake_session('a', 'running'), fake_session('b', 'idle'), fake_session('c', 'running') }, 4)

    eq(2, a:running())
  end)

  it('lets a running session carry on, and admits others only below the limit', function()
    local busy = fake_session('busy', 'running')
    local idle = fake_session('idle', 'idle')
    local a = admission({ busy }, 1)

    eq(true, a:allows(busy))
    eq(false, a:allows(idle))
    eq(true, admission({ busy }, 2):allows(idle))
  end)

  it('reads the limit when asked, so a changed setting applies', function()
    local limit = 1
    local busy = fake_session('busy', 'running')
    local a = Admission({
      store = fake_store({ busy }),
      limit = function()
        return limit
      end,
    })
    local idle = fake_session('idle', 'idle')

    eq(false, a:allows(idle))
    limit = 3
    eq(true, a:allows(idle))
  end)

  it('lists idle sessions with queued prompts, the longest waiting first', function()
    local late = fake_session('late', 'idle', 1, 20)
    local early = fake_session('early', 'idle', 2, 10)
    local nothing = fake_session('nothing', 'idle', 0)
    local a = admission({ late, nothing, early, fake_session('busy', 'running', 1, 5) }, 4)

    eq(
      { 'early', 'late' },
      vim.tbl_map(function(session)
        return session.name
      end, a:waiting())
    )
  end)

  it('releases waiting sessions one by one until the limit is reached', function()
    local first = fake_session('first', 'idle', 1, 1)
    local second = fake_session('second', 'idle', 1, 2)
    local third = fake_session('third', 'idle', 1, 3)

    admission({ third, first, second }, 2):release()

    eq({ true, true, false }, { first.drained, second.drained, third.drained })
  end)
end)

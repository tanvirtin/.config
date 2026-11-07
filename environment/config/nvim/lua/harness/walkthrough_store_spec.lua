local walkthrough_store = require('harness.walkthrough_store')

local eq = assert.are.same

describe('harness.walkthrough_store:', function()
  before_each(function()
    walkthrough_store.reset()
  end)

  after_each(function()
    walkthrough_store.reset()
  end)

  it('holds each session its own walkthrough, and tells whoever listens which one starts or stops', function()
    local seen = {}

    walkthrough_store.on(function(kind, session, walkthrough)
      seen[#seen + 1] = { kind, session, walkthrough.title }
    end)

    local started = walkthrough_store.start('s1', { title = 'a', steps = {} })

    eq(started, walkthrough_store.current('s1'))
    eq(nil, walkthrough_store.current('s2'))
    eq({ { 'start', 's1', 'a' } }, seen)

    walkthrough_store.start('s2', { title = 'b', steps = {} })
    walkthrough_store.stop('s1')

    eq(nil, walkthrough_store.current('s1'))
    eq('b', walkthrough_store.current('s2').title)
    eq({ { 'start', 's1', 'a' }, { 'start', 's2', 'b' }, { 'stop', 's1', 'a' } }, seen)
  end)

  it('refuses a walkthrough that is not tied to a session', function()
    assert.has_error(function()
      walkthrough_store.start({ title = 'a', steps = {} })
    end)

    assert.has_error(function()
      walkthrough_store.current()
    end)
  end)

  it('keeps the newest walkthroughs of a session, newest first, up to a limit', function()
    for i = 1, walkthrough_store.RECENT + 3 do
      walkthrough_store.start('s1', { title = 't' .. i, steps = {} })
    end
    walkthrough_store.start('s2', { title = 'other', steps = {} })

    local recent = walkthrough_store.recent('s1')

    eq(walkthrough_store.RECENT, #recent)
    eq('t' .. walkthrough_store.RECENT + 3, recent[1].title)
    eq(1, #walkthrough_store.recent('s2'))
  end)

  it('stops listening once the disposer is called, and stopping nothing says nothing', function()
    local calls = 0
    local dispose = walkthrough_store.on(function()
      calls = calls + 1
    end)

    dispose()
    walkthrough_store.start('s1', { title = 'a', steps = {} })
    walkthrough_store.reset()
    walkthrough_store.stop('s1')

    eq(0, calls)
  end)

  it(
    'passes an update to the listeners of the session whose walkthrough is running, and refuses without one',
    function()
      local seen = {}

      walkthrough_store.on(function(kind, session, walkthrough, update)
        seen[#seen + 1] = { kind, session, walkthrough.title, update.mode }
      end)

      eq(false, (walkthrough_store.update('s1', { mode = 'note' })))
      eq({}, seen)

      walkthrough_store.start('s1', { title = 'a', steps = {} })
      eq(true, walkthrough_store.update('s1', { mode = 'note' }))
      eq(false, (walkthrough_store.update('s2', { mode = 'note' })))

      eq({ { 'start', 's1', 'a', nil }, { 'update', 's1', 'a', 'note' } }, seen)
    end
  )

  it('tells a running walkthrough about a selection, and says nothing without one', function()
    local seen = {}

    walkthrough_store.on(function(kind, session, walkthrough, update)
      if kind == 'select' then
        seen[#seen + 1] = { session, update.path, update.first, update.last, walkthrough.title }
      end
    end)

    eq(false, walkthrough_store.select('s1', '/w/a.lua', 1, 2))
    eq({}, seen)

    walkthrough_store.start('s1', { title = 'a', steps = {} })
    eq(true, walkthrough_store.select('s1', '/w/a.lua', 1, 2))
    eq({ { 's1', '/w/a.lua', 1, 2, 'a' } }, seen)
  end)

  it('remembers the range being reviewed for one session only', function()
    walkthrough_store.set_scope('s1', { head = 'abc' })

    eq({ head = 'abc' }, walkthrough_store.scope('s1'))
    eq(nil, walkthrough_store.scope('s2'))

    walkthrough_store.start('s1', { title = 'a', steps = {} })
    walkthrough_store.stop('s1')

    eq(nil, walkthrough_store.scope('s1'))
  end)
end)

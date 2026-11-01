local tour_store = require('harness.tour_store')

local eq = assert.are.same

describe('harness.tour_store:', function()
  before_each(function()
    tour_store.reset()
  end)

  after_each(function()
    tour_store.reset()
  end)

  it('holds each session its own tour, and tells whoever listens which one starts or stops', function()
    local seen = {}

    tour_store.on(function(kind, session, tour)
      seen[#seen + 1] = { kind, session, tour.title }
    end)

    local started = tour_store.start('s1', { title = 'a', steps = {} })

    eq(started, tour_store.current('s1'))
    eq(nil, tour_store.current('s2'))
    eq({ { 'start', 's1', 'a' } }, seen)

    tour_store.start('s2', { title = 'b', steps = {} })
    tour_store.stop('s1')

    eq(nil, tour_store.current('s1'))
    eq('b', tour_store.current('s2').title)
    eq({ { 'start', 's1', 'a' }, { 'start', 's2', 'b' }, { 'stop', 's1', 'a' } }, seen)
  end)

  it('refuses a tour that is not tied to a session', function()
    assert.has_error(function()
      tour_store.start({ title = 'a', steps = {} })
    end)

    assert.has_error(function()
      tour_store.current()
    end)
  end)

  it('keeps the newest tours of a session, newest first, up to a limit', function()
    for i = 1, tour_store.RECENT + 3 do
      tour_store.start('s1', { title = 't' .. i, steps = {} })
    end
    tour_store.start('s2', { title = 'other', steps = {} })

    local recent = tour_store.recent('s1')

    eq(tour_store.RECENT, #recent)
    eq('t' .. tour_store.RECENT + 3, recent[1].title)
    eq(1, #tour_store.recent('s2'))
  end)

  it('stops listening once the disposer is called, and stopping nothing says nothing', function()
    local calls = 0
    local dispose = tour_store.on(function()
      calls = calls + 1
    end)

    dispose()
    tour_store.start('s1', { title = 'a', steps = {} })
    tour_store.reset()
    tour_store.stop('s1')

    eq(0, calls)
  end)

  it('passes an update to the listeners of the session whose tour is running, and refuses without one', function()
    local seen = {}

    tour_store.on(function(kind, session, tour, update)
      seen[#seen + 1] = { kind, session, tour.title, update.mode }
    end)

    eq(false, (tour_store.update('s1', { mode = 'note' })))
    eq({}, seen)

    tour_store.start('s1', { title = 'a', steps = {} })
    eq(true, tour_store.update('s1', { mode = 'note' }))
    eq(false, (tour_store.update('s2', { mode = 'note' })))

    eq({ { 'start', 's1', 'a', nil }, { 'update', 's1', 'a', 'note' } }, seen)
  end)

  it('remembers the range being reviewed for one session only', function()
    tour_store.set_scope('s1', { head = 'abc' })

    eq({ head = 'abc' }, tour_store.scope('s1'))
    eq(nil, tour_store.scope('s2'))

    tour_store.start('s1', { title = 'a', steps = {} })
    tour_store.stop('s1')

    eq(nil, tour_store.scope('s1'))
  end)
end)

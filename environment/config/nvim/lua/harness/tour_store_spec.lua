local tour_store = require('harness.tour_store')

local eq = assert.are.same

describe('harness.tour_store:', function()
  before_each(function()
    tour_store.reset()
  end)

  after_each(function()
    tour_store.reset()
  end)

  it('holds the tour being followed, and tells whoever listens when one starts or stops', function()
    local seen = {}

    tour_store.on(function(kind, tour)
      seen[#seen + 1] = { kind, tour.title }
    end)

    local started = tour_store.start({ title = 'a', steps = {} })

    eq(started, tour_store.current())
    eq({ { 'start', 'a' } }, seen)

    tour_store.stop()

    eq(nil, tour_store.current())
    eq({ { 'start', 'a' }, { 'stop', 'a' } }, seen)
  end)

  it('keeps the newest tours, newest first, up to a limit', function()
    for i = 1, tour_store.RECENT + 3 do
      tour_store.start({ title = 't' .. i, steps = {} })
    end

    local recent = tour_store.recent()

    eq(tour_store.RECENT, #recent)
    eq('t' .. tour_store.RECENT + 3, recent[1].title)
  end)

  it('stops listening once the disposer is called, and stopping nothing says nothing', function()
    local calls = 0
    local dispose = tour_store.on(function()
      calls = calls + 1
    end)

    dispose()
    tour_store.start({ title = 'a', steps = {} })
    tour_store.reset()
    tour_store.stop()

    eq(0, calls)
  end)

  it('passes an update to the listeners of the tour that is running, and refuses without one', function()
    local seen = {}

    tour_store.on(function(kind, tour, update)
      seen[#seen + 1] = { kind, tour.title, update.mode }
    end)

    eq(false, (tour_store.update({ mode = 'note' })))
    eq({}, seen)

    tour_store.start({ title = 'a', steps = {} })
    eq(true, tour_store.update({ mode = 'note' }))

    eq({ { 'start', 'a', nil }, { 'update', 'a', 'note' } }, seen)
  end)
end)

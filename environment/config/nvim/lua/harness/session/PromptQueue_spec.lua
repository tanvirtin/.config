local PromptQueue = require('harness.session.PromptQueue')
local events = require('harness.events')
local fake = require('harness.session.fake_session')

local eq = assert.are.same

describe('harness.session.PromptQueue:', function()
  it('sends right away when idle, and holds messages while a turn runs', function()
    local session = fake.session()
    local queue = PromptQueue(session)

    queue:enqueue('now')
    eq({ 'now' }, session.prompted)

    session.state = 'running'
    queue:enqueue('later')
    queue:enqueue('much later')

    eq({ 'later', 'much later' }, queue:queued())

    session.state = 'idle'
    queue:drain()

    eq({ 'now', 'later' }, session.prompted)
    eq({ 'much later' }, queue:queued())
  end)

  it('hands everything back, emptying the same table', function()
    local session = fake.session()
    local queue = PromptQueue(session)
    local items = queue.items

    session.state = 'running'
    queue:enqueue('a')
    queue:enqueue('b')

    eq({ 'a', 'b' }, queue:take_all())
    eq(items, queue.items)
    eq(0, queue:size())
    eq(true, vim.tbl_contains(session.notified, events.NOTICE.queue))
  end)

  it('does not send while the session reloads', function()
    local session = fake.session()
    local queue = PromptQueue(session)

    session.reloading = true
    queue:enqueue('wait')

    eq({}, session.prompted)
    eq({ 'wait' }, queue:queued())
  end)

  it('queues a steer the agent cannot take', function()
    local session = fake.session({
      connection = {
        steering = function()
          return false
        end,
      },
    })
    local queue = PromptQueue(session)

    session.state = 'running'
    queue:steer('turn left')

    eq({ 'turn left' }, queue:queued())
    eq({}, session.emitted)
  end)
end)

local Subagents = require('harness.session.Subagents')
local events = require('harness.types.events')
local fake = require('harness.session.fake_session')

local eq = assert.are.same

describe('harness.session.Subagents:', function()
  local attached, handled, session, subagents

  before_each(function()
    attached, handled = {}, {}
    session = fake.session({
      connection = {
        attach = function(_, id, listener)
          attached[id] = listener
        end,
        detach = function(_, id)
          attached[id] = nil
        end,
      },
    })
    session.is_state_event = function()
      return false
    end
    function session:_handle(event)
      handled[#handled + 1] = event
    end
    subagents = Subagents(session)
  end)

  it('follows a new child once, and keeps its latest state', function()
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1', title = 'Explore', state = 'running' }))
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1', state = 'idle', stop = 'end_turn' }))

    eq({ id = 'c1', title = 'Explore', state = 'idle', stop = 'end_turn' }, subagents.children.c1)
    eq('table', type(attached.c1))
  end)

  it('files the child\'s work under the tool call that delegated to it', function()
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1' }))
    attached.c1.event(events.new({ kind = events.KIND.delegation, message = 'task1' }))
    attached.c1.event(events.new({ kind = events.KIND.message, text = 'done' }))

    eq('task1', handled[1].parent)
    eq({ events.KIND.subagent }, session.notified)
  end)

  it('wakes the parent when a child finishes after the turn ended', function()
    local Watch = require('harness.session.Watch')
    local wake = require('harness.settings.wake')
    local settle_ms = wake:get('settle_ms')

    wake:assign({ settle_ms = 1 })
    session.watch = Watch(session)

    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1', title = 'Explore', state = 'running' }))
    session.watch:turn_ended('end_turn')
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1', state = 'idle', stop = 'end_turn' }))

    vim.wait(80, function()
      return (session.queued or {})[1] ~= nil
    end)

    eq(1, #(session.queued or {}))
    assert.is_truthy(session.queued[1].text:find('Explore', 1, true))

    wake:assign({ settle_ms = settle_ms })
  end)

  it('stays quiet when the child finished inside the turn', function()
    local Watch = require('harness.session.Watch')
    local wake = require('harness.settings.wake')
    local settle_ms = wake:get('settle_ms')

    wake:assign({ settle_ms = 1 })
    session.watch = Watch(session)

    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1', title = 'Explore', state = 'running' }))
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1', state = 'idle', stop = 'end_turn' }))
    session.watch:turn_ended('end_turn')

    vim.wait(40)

    eq(nil, (session.queued or {})[1])

    wake:assign({ settle_ms = settle_ms })
  end)

  it('stops listening to every child', function()
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1' }))
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c2' }))
    subagents:detach_all()

    eq({}, attached)
  end)

  it('counts the running children and how long the quietest has been silent', function()
    local Timer = require('core.Timer')
    local now = Timer.now

    Timer.now = function()
      return 1000
    end

    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1', state = 'running' }))
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c2', state = 'running' }))
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c3', state = 'idle' }))
    subagents.children.c1.tool = 't1'
    subagents.children.c2.tool = 't2'
    subagents.children.c3.tool = 't3'

    Timer.now = function()
      return 61000
    end

    attached.c2.event(events.new({ kind = events.KIND.message, text = 'still here' }))

    Timer.now = function()
      return 91000
    end

    local summary = subagents:summary()
    Timer.now = now

    eq({ active = 2, quiet = 90000 }, summary)
  end)
end)

local Subagents = require('harness.session.Subagents')
local events = require('harness.events')
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
    attached.c1.update({ sessionUpdate = 'session_message', messageId = 'task1', content = {} })
    attached.c1.update({ sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'done' } })

    eq('task1', handled[1].parent)
    eq({ events.KIND.subagent }, session.notified)
  end)

  it('stops listening to every child', function()
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c1' }))
    subagents:apply(events.new({ kind = events.KIND.subagent, child = 'c2' }))
    subagents:detach_all()

    eq({}, attached)
  end)
end)

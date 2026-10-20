local History = require('harness.session.History')
local events = require('harness.events')

local eq = assert.are.same

local function user(text)
  return { kind = events.KIND.user, text = text }
end

local function reply(text)
  return { kind = events.KIND.message, text = text }
end

describe('harness.session.History:', function()
  it('appends typed events with the time they arrived, joining streamed text', function()
    local history = History()

    eq(true, history:append(reply('a')))
    history:append(reply('b'))

    eq(1, #history.events)
    eq('ab', history:last().text)
    eq(true, events.TYPES[events.KIND.message].is(history:last()))
    eq('number', type(history.times[1]))
  end)

  it('collects a replay apart, then adopts only what is new, keeping its tables', function()
    local history = History()
    local list, times = history.events, history.times

    history:append(user('one'))
    history:append(reply('first'))
    history:append({ kind = events.KIND.stop, reason = 'end_turn' })
    history:begin_replay()

    eq(true, history:replaying())

    for _, event in ipairs({ user('one'), reply('first'), user('two'), reply('second') }) do
      eq(false, history:append(event))
    end

    eq(events.NOTICE.appended, history:end_replay(true))
    eq(list, history.events)
    eq(times, history.times)
    eq(
      { 'user', 'message', 'stop', 'user', 'message' },
      vim.tbl_map(function(event)
        return event.kind
      end, history.events)
    )
  end)

  it('changes nothing when the replay is behind, and replaces everything when it disagrees', function()
    local history = History()

    history:append(user('one'))
    history:append(reply('first'))
    history:append(user('two'))
    history:begin_replay()
    history:append(user('one'))

    eq(nil, history:end_replay(true))
    eq(3, #history.events)

    history:begin_replay()
    history:append(user('other'))

    eq(events.NOTICE.reset, history:end_replay(true))
    eq({ user('other') }, history.events)
  end)

  it('drops a failed replay', function()
    local history = History()

    history:append(user('one'))
    history:begin_replay()
    history:append(user('two'))

    eq(nil, history:end_replay(false))
    eq(1, #history.events)
    eq(false, history:replaying())
  end)
end)

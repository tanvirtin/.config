local History = require('harness.session.History')
local events = require('harness.types.events')

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

  it('keeps its own history when the agent echoes a prompt with its attachments written in', function()
    local history = History()

    history:append(user('tour it, start with @src/main.rs and explain dispatch'))
    history:append(reply('first'))
    history:append({ kind = events.KIND.stop, reason = 'end_turn' })
    history:begin_replay()

    for _, event in ipairs({
      user('tour it, start with @src/main.rs[/w/src/main.rs:1]\nuse clap::Parser;\n and explain dispatch'),
      reply('first'),
    }) do
      history:append(event)
    end

    eq(nil, history:end_replay(true))
    eq('tour it, start with @src/main.rs and explain dispatch', history.events[1].text)
  end)

  it('still sees a different prompt as a divergence', function()
    local history = History()

    history:append(user('rename the parser'))
    history:append(reply('first'))
    history:begin_replay()
    history:append(user('delete the tests'))
    history:append(reply('other'))

    eq(events.NOTICE.reset, history:end_replay(true))
  end)

  describe('after a finished turn, with no new prompt in the replay', function()
    local function finished()
      local history = History()

      history:append(user('one'))
      history:append(reply('first'))
      history:append({ kind = events.KIND.stop, reason = 'end_turn' })

      return history
    end

    local function kinds(history)
      return vim.tbl_map(function(event)
        return event.kind .. (event.text and (':' .. event.text) or '')
      end, history.events)
    end

    it('adopts what the agent wrote after the turn ended, keeping the stop', function()
      local history = finished()

      history:begin_replay()
      for _, event in ipairs({ user('one'), reply('first'), { kind = events.KIND.tool_call, id = 't1' }, reply('late') }) do
        history:append(event)
      end

      eq(events.NOTICE.appended, history:end_replay(true))
      eq({ 'user:one', 'message:first', 'stop', 'tool_call', 'message:late' }, kinds(history))
      eq(#history.events, #history.times)
    end)

    it('adds only the new text when the last reply grew', function()
      local history = finished()

      history:begin_replay()
      history:append(user('one'))
      history:append(reply('first and more'))

      eq(events.NOTICE.appended, history:end_replay(true))
      eq({ 'user:one', 'message:first', 'stop', 'message: and more' }, kinds(history))
    end)

    it('changes nothing when the replay holds nothing new', function()
      local history = finished()

      history:begin_replay()
      history:append(user('one'))
      history:append(reply('first'))

      eq(nil, history:end_replay(true))
      eq({ 'user:one', 'message:first', 'stop' }, kinds(history))
    end)

    it('adopts nothing when what it already shows disagrees with the replay', function()
      local history = finished()

      history:begin_replay()
      history:append(user('one'))
      history:append(reply('other'))
      history:append({ kind = events.KIND.tool_call, id = 't1' })

      eq(nil, history:end_replay(true))
      eq({ 'user:one', 'message:first', 'stop' }, kinds(history))
    end)
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

  it('keeps its turn index equal to a scan through appends, adoption and reindexing', function()
    local TurnIndex = require('harness.session.TurnIndex')
    local history = History()

    local function same()
      local scanned = TurnIndex():rebuild(history.events)

      eq(scanned.starts, history.turns.starts)
      eq(scanned.updates, history.turns.updates)
      eq(scanned.late, history.turns.late)
      eq(true, history.turns:fresh(history.events))
    end

    history:append(user('one'))
    history:append({ kind = events.KIND.tool_call, id = 'a' })
    history:append(reply('first'))
    history:append(reply(' more'))
    history:append(user('two'))
    history:append({ kind = events.KIND.tool_update, id = 'a', status = 'completed' })
    same()
    eq({ 1, 4 }, history.turns.starts)

    history:begin_replay()

    for _, event in ipairs({ user('one'), reply('first'), user('two'), reply('second'), user('three') }) do
      history:append(event)
    end

    history:end_replay(true)
    same()

    history:append({ kind = events.KIND.prompt, text = 'steer', steered = true })
    history.events[#history.events].steered = nil
    history:reindex()
    same()
  end)

  describe('the current turn', function()
    local K = events.KIND

    local function turn(list)
      local history = History()

      for _, event in ipairs(list) do
        history:append(event)
      end

      return history
    end

    it('starts at the last prompt, or at the first event when there is none', function()
      eq(1, History():turn_start())
      eq(
        3,
        turn({ { kind = K.prompt, text = 'a' }, reply('x'), { kind = K.prompt, text = 'b' }, reply('y') }):turn_start()
      )
    end)

    it('lists its tools latest first with their newest status and diffs, ignoring earlier turns', function()
      local diffs = { { path = 'a.rs', old = 'a', new = 'b' } }
      local history = turn({
        { kind = K.prompt, text = 'old' },
        { kind = K.tool_call, id = 'gone', status = 'completed' },
        { kind = K.prompt, text = 'now' },
        { kind = K.tool_call, id = 't1', status = 'in_progress' },
        { kind = K.tool_call, id = 't2', status = 'in_progress' },
        { kind = K.tool_update, id = 't1', status = 'completed', diffs = diffs },
      })

      local tools = history:turn_tools()

      eq({ 't1', 't2' }, { tools[1].id, tools[2].id })
      eq({ 'completed', 'in_progress' }, { tools[1].status, tools[2].status })
      eq(diffs, tools[1].diffs)
      eq(nil, tools[2].diffs)
    end)

    it('knows which tool calls the user was asked about', function()
      local history = turn({
        { kind = K.prompt, text = 'now' },
        events.permission('edit', true, { id = 't2' }),
      })

      eq({ t2 = true }, history:turn_asked())
    end)
  end)
end)

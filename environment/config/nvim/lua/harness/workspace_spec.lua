local Workspace = require('harness.workspace')
local agent = require('harness.agent')
local async = require('harness.async')
local fake_agent = require('harness.servers.acp.fake_agent')
local jsonrpc = require('harness.servers.acp.jsonrpc')

local eq = assert.are.same

local function run(fn)
  return async.run(fn):wait()
end

local claude = agent.Agent(
  'claude',
  { command = 'claude-agent-acp', system = 'be brief', model = 'claude-sonnet-5-5', fork_at_message = true }
)

local function workspace(script)
  local spawned = {}
  local ws = Workspace('/w', {
    spawn = function(a, dir)
      local fake = fake_agent.new(script)
      spawned[#spawned + 1] = { agent = a.name, dir = dir, fake = fake }
      return fake
    end,
    servers = function(_, key)
      return { { name = 'nvim', command = 'nvim', args = {}, env = { { name = 'HARNESS_SESSION', value = key } } } }
    end,
  })

  return ws, spawned
end

describe('harness.workspace:', function()
  it('runs every session of an agent on one process', function()
    local ws, spawned = workspace()

    local both = run(function()
      return { ws:new_session(claude, { key = 'h1' }), ws:new_session(claude, { key = 'h2' }) }
    end)
    local one, two = both[1], both[2]

    local fake = spawned[1].fake

    eq(1, #spawned)
    eq('/w', spawned[1].dir)
    eq(1, fake:count('initialize'))
    eq(2, fake:count('session/new'))
    eq({ 's1', 's2' }, { one.id, two.id })
    eq(one.connection, two.connection)
    eq(ws.sessions.h2, two)
  end)

  it('gives each session its directory, servers and the agent\'s system prompt', function()
    local ws, spawned = workspace()

    run(function()
      ws:new_session(claude, { key = 'h7' })
    end)

    local new = spawned[1].fake:sent_method('session/new')

    eq('/w', new.params.cwd)
    eq('h7', new.params.mcpServers[1].env[1].value)
    eq('be brief', new.params.systemPrompt.content[1].text)
  end)

  it('puts every session, new or loaded, on the agent\'s model', function()
    local ws, spawned = workspace()

    run(function()
      ws:new_session(claude, { key = 'h1' })
      ws:load_session(claude, 'old', { key = 'h2' })
    end)

    local sets = vim.tbl_filter(function(message)
      return message.method == 'session/set_config_option'
    end, spawned[1].fake.sent)

    eq(2, #sets)
    eq({ sessionId = 's1', configId = 'model', value = 'claude-sonnet-5-5' }, sets[1].params)
    eq('old', sets[2].params.sessionId)
  end)

  it('falls back to session/set_model, and starts anyway with a warning when the agent refuses the model', function()
    local models = {}
    local ws = workspace({
      ['session/set_config_option'] = function(message)
        return { jsonrpc.error(message.id, jsonrpc.INTERNAL_ERROR, 'Invalid value for config option model') }
      end,
      ['session/set_model'] = function(message)
        models[#models + 1] = message.params.modelId
        return { jsonrpc.error(message.id, jsonrpc.INTERNAL_ERROR, 'unknown model') }
      end,
    })
    local warned = {}
    local notify = vim.notify

    vim.notify = function(message)
      warned[#warned + 1] = message
    end

    local ok, session = pcall(run, function()
      return ws:new_session(claude, { key = 'h1' })
    end)

    vim.wait(500, function()
      return #warned > 0
    end)
    vim.notify = notify

    eq(true, ok)
    eq({ 'claude-sonnet-5-5' }, models)
    assert.is_truthy(session)
    assert.is_truthy(table.concat(warned, '\n'):find('could not use model claude-sonnet-5-5', 1, true))
  end)

  it('starts a new process after the last one exited', function()
    local ws, spawned = workspace()

    run(function()
      ws:new_session(claude, { key = 'h1' })
    end)
    spawned[1].fake:exit(0)
    run(function()
      ws:new_session(claude, { key = 'h2' })
    end)

    eq(2, #spawned)
  end)

  it('tries again after a failed start', function()
    local fail = true
    local ws, spawned = workspace({
      initialize = function(message)
        if fail then return { jsonrpc.error(message.id, jsonrpc.INTERNAL_ERROR, 'no auth') } end
        return { jsonrpc.result(message.id, { protocolVersion = 1 }) }
      end,
    })

    eq(
      false,
      pcall(run, function()
        ws:new_session(claude, { key = 'h1' })
      end)
    )

    fail = false
    run(function()
      ws:new_session(claude, { key = 'h2' })
    end)

    eq(2, #spawned)
  end)

  it('lists live sessions first, then stored ones it does not already show', function()
    local ws, spawned = workspace()

    run(function()
      ws:new_session(claude, { key = 'h1' })
    end)
    spawned[1].fake.stored = {
      { sessionId = 's1', cwd = '/w', title = 'live one' },
      { sessionId = 'old', cwd = '/w', title = 'yesterday', updatedAt = '2026-10-16T10:00:00Z' },
    }

    local items = run(function()
      return ws:list(claude)
    end)

    eq(2, #items)
    eq('s1', items[1].id)
    eq(ws.sessions.h1, items[1].session)
    eq({ id = 'old', title = 'yesterday', updated_at = '2026-10-16T10:00:00Z' }, items[2])
    eq('/w', spawned[1].fake:sent_method('session/list').params.cwd)
  end)

  it('keeps the modes and options an agent reports when a session starts', function()
    local ws = workspace({
      ['session/new'] = function(message)
        return {
          jsonrpc.result(message.id, {
            sessionId = 's1',
            modes = { currentModeId = 'default', availableModes = { { id = 'default', name = 'Manual' } } },
            configOptions = { { id = 'effort', category = 'thought_level', currentValue = 'high', options = {} } },
          }),
        }
      end,
    })

    local session = run(function()
      return ws:new_session(claude, { key = 'h1' })
    end)

    eq('Manual', session:mode().name)
    eq('high', session:option('effort').current)
  end)

  it('loads a stored session, replaying its history', function()
    local ws, spawned = workspace()

    run(function()
      ws:connection(claude)
    end)
    spawned[1].fake.histories.old = {
      { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'rename x' } },
      { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'done' } },
    }

    local session = run(function()
      return ws:load_session(claude, 'old', { key = 'h3', title = 'yesterday' })
    end)

    eq('old', session.id)
    eq('yesterday', session.title)
    eq({ { kind = 'user', text = 'rename x' }, { kind = 'message', text = 'done' } }, session.history)
    eq(session, ws:find('old'))
  end)

  it('forks a session at a reply and opens the fork with the history up to it', function()
    local ws, spawned = workspace({
      initialize = function(message)
        return {
          jsonrpc.result(message.id, {
            protocolVersion = 1,
            agentCapabilities = { loadSession = true, sessionCapabilities = { fork = {} } },
          }),
        }
      end,
    })

    run(function()
      ws:connection(claude)
    end)

    local fake = spawned[1].fake

    fake.histories.old = {
      { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'one' } },
      { sessionUpdate = 'agent_message_chunk', messageId = 'm1', content = { type = 'text', text = 'first' } },
      { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'two' } },
      { sessionUpdate = 'agent_message_chunk', messageId = 'm2', content = { type = 'text', text = 'second' } },
    }

    local source = run(function()
      return ws:load_session(claude, 'old', { key = 'h1' })
    end)
    local forked = run(function()
      return ws:fork(source, 'm1', { key = 'h2' })
    end)

    eq({ source = 'old', message_id = 'm1' }, fake.forked)
    eq({ { kind = 'user', text = 'one' }, { kind = 'message', text = 'first', message_id = 'm1' } }, forked.history)
    eq(4, #source.history)
  end)

  describe('reload', function()
    local function loaded()
      local ws, spawned = workspace()

      run(function()
        ws:connection(claude)
      end)

      local fake = spawned[1].fake

      fake.histories.old = {
        { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'rename x' } },
        { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'done' } },
      }

      local session = run(function()
        return ws:load_session(claude, 'old', { key = 'h3' })
      end)

      return ws, session, fake
    end

    it('replays what another program added, swapping the history in at once', function()
      local ws, session, fake = loaded()
      local seen = {}

      session:subscribe(function(event)
        seen[#seen + 1] = event.kind
      end)
      table.insert(
        fake.histories.old,
        { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'and y' } }
      )
      table.insert(
        fake.histories.old,
        { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'renamed y' } }
      )

      local changed = run(function()
        return ws:reload(session)
      end)

      eq(true, changed)
      eq({ 'appended' }, seen)
      eq({
        { kind = 'user', text = 'rename x' },
        { kind = 'message', text = 'done' },
        { kind = 'user', text = 'and y' },
        { kind = 'message', text = 'renamed y' },
      }, session.history)
      eq(2, fake:count('session/load'))
    end)

    it('keeps what only this editor knows, such as turn endings, when another program adds a turn', function()
      local ws, session, fake = loaded()

      session:_emit({ kind = 'stop', reason = 'end_turn' })
      session:_emit({ kind = 'permission', tool = 'Bash', allowed = false })
      table.insert(
        fake.histories.old,
        { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'more' } }
      )

      eq(
        true,
        run(function()
          return ws:reload(session)
        end)
      )
      eq(
        { 'user', 'message', 'stop', 'permission', 'user' },
        vim.tbl_map(function(event)
          return event.kind
        end, session.history)
      )
    end)

    it('fills in a turn from another program as it is written, prompt first and reply later', function()
      local ws, session, fake = loaded()

      table.insert(
        fake.histories.old,
        { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'next' } }
      )
      eq(
        true,
        run(function()
          return ws:reload(session)
        end)
      )

      table.insert(
        fake.histories.old,
        { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'reply' } }
      )
      eq(
        true,
        run(function()
          return ws:reload(session)
        end)
      )
      eq({ kind = 'message', text = 'reply' }, session.history[#session.history])
      eq(4, #session.history)

      eq(
        false,
        run(function()
          return ws:reload(session)
        end)
      )
    end)

    it('never rewrites a turn this editor ran itself', function()
      local ws, session = loaded()

      session:_emit({ kind = 'prompt', text = 'mine' })
      session:_emit({ kind = 'message', text = 'my reply' })
      session:_emit({ kind = 'stop', reason = 'end_turn' })

      local before = vim.deepcopy(session.history)

      run(function()
        return ws:reload(session)
      end)

      eq(before, session.history)
    end)

    it('swaps in the replay when it no longer matches what this editor shows', function()
      local ws, session, fake = loaded()
      local seen = {}

      session:subscribe(function(event)
        seen[#seen + 1] = event.kind
      end)
      fake.histories.old = {
        { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'something else' } },
      }

      eq(
        true,
        run(function()
          return ws:reload(session)
        end)
      )
      eq({ { kind = 'user', text = 'something else' } }, session.history)
      eq({ 'reset' }, seen)
    end)

    it('matches its own prompts against the replay, ignoring the editor context sent with them', function()
      local ws, session, fake = loaded()

      session:_emit({ kind = 'prompt', text = 'mine' })
      table.insert(fake.histories.old, {
        sessionUpdate = 'user_message_chunk',
        content = { type = 'text', text = '<editor-context>at a.lua</editor-context>\n\nmine' },
      })

      eq(
        false,
        run(function()
          return ws:reload(session)
        end)
      )
      eq('prompt', session.history[#session.history].kind)
    end)

    it('reports no change when nothing was added, keeping when things first arrived', function()
      local ws, session = loaded()
      local times = vim.deepcopy(session.times)

      vim.wait(20)

      eq(
        false,
        run(function()
          return ws:reload(session)
        end)
      )
      eq(times, session.times)
    end)

    it('does not reload over a running turn, and sends what was queued during a reload once it is done', function()
      local ws, session, fake = loaded()

      session.state = 'running'
      eq(
        false,
        run(function()
          return ws:reload(session)
        end)
      )
      session.state = 'idle'

      session:begin_replay()
      session:enqueue('queued while loading')
      eq(0, fake:count('session/prompt'))
      session:end_replay(true)
      vim.wait(200, function()
        return fake:count('session/prompt') == 1
      end)

      eq(1, fake:count('session/prompt'))
    end)
  end)

  it('closes every session and process', function()
    local ws, spawned = workspace()
    local session = run(function()
      return ws:new_session(claude, { key = 'h1' })
    end)

    ws:close()

    eq(true, spawned[1].fake.closed)
    eq('closed', session.state)
    eq({}, ws.sessions)
  end)
end)

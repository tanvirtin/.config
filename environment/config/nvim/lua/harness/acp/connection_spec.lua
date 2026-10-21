local Connection = require('harness.acp.connection')
local async = require('harness.async')
local fake_agent = require('harness.fake_agent')
local jsonrpc = require('harness.acp.jsonrpc')

local eq = assert.are.same

local function run(fn)
  return async.run(fn):wait()
end

local function connected(script)
  local agent = fake_agent.new(script)
  local conn = Connection(agent)

  run(function()
    conn:initialize()
  end)

  return conn, agent
end

local function listener(log)
  return {
    update = function(update)
      log[#log + 1] = update.sessionUpdate
    end,
  }
end

describe('harness.acp.connection:', function()
  it('initializes and keeps the agent\'s capabilities', function()
    local conn = connected()

    eq(true, conn.capabilities.loadSession)
    eq(true, conn:supports('list'))
    eq(false, conn:supports('fork'))
  end)

  it('routes each session\'s updates to its listener', function()
    local conn, agent = connected()
    local one, two = {}, {}

    conn:attach('s1', listener(one))
    conn:attach('s2', listener(two))
    agent:push(fake_agent.chunk('s1', 'a'), fake_agent.chunk('s2', 'b'), fake_agent.chunk('s1', 'c'))

    eq({ 'agent_message_chunk', 'agent_message_chunk' }, one)
    eq({ 'agent_message_chunk' }, two)
  end)

  it('keeps updates that arrive before a session is attached', function()
    local conn, agent = connected()
    local seen = {}

    agent:push(fake_agent.update('s9', { sessionUpdate = 'available_commands_update' }))
    conn:attach('s9', listener(seen))

    eq({ 'available_commands_update' }, seen)
  end)

  it('creates and prompts a session', function()
    local conn, agent = connected()

    local result = run(function()
      local id = conn:new_session({ cwd = '/w', mcp_servers = {}, system_prompt = 'be brief' }).sessionId
      return conn:prompt(id, { { type = 'text', text = 'hi' } })
    end)

    local new = agent:sent_method('session/new')

    eq('end_turn', result.stopReason)
    eq('/w', new.params.cwd)
    eq({ mode = 'append', content = { { type = 'text', text = 'be brief' } } }, new.params.systemPrompt)
  end)

  it('loads a session, streaming its history to the listener first', function()
    local conn, agent = connected()
    local seen = {}

    agent.histories.old = { { sessionUpdate = 'user_message_chunk', content = { type = 'text', text = 'q' } } }
    conn:attach('old', listener(seen))
    run(function()
      conn:load_session('old', { cwd = '/w' })
    end)

    eq({ 'user_message_chunk' }, seen)
    eq('old', agent:sent_method('session/load').params.sessionId)
  end)

  it('lists stored sessions across pages', function()
    local pages = 0
    local conn = connected({
      ['session/list'] = function(message)
        pages = pages + 1

        if message.params.cursor then return { jsonrpc.result(message.id, { sessions = { { sessionId = 'b' } } }) } end

        return { jsonrpc.result(message.id, { sessions = { { sessionId = 'a' } }, nextCursor = 'offset:1' }) }
      end,
    })

    local sessions = run(function()
      return conn:list_sessions('/w')
    end)

    eq({ { sessionId = 'a' }, { sessionId = 'b' } }, sessions)
    eq(2, pages)
  end)

  it('answers a permission request with what the listener decides, even later', function()
    local conn, agent = connected()
    local answer = async.Future.new()

    conn:attach('s1', {
      update = function() end,
      request = function(method)
        eq('session/request_permission', method)
        return answer
      end,
    })
    agent:push(fake_agent.permission('s1', 'Bash'))

    eq(nil, agent:selected())

    answer:set_result({ outcome = { outcome = 'selected', optionId = 'allow' } })
    async.drain()

    eq('allow', agent:selected())
  end)

  it('sends an answer that is already known at once', function()
    local conn, agent = connected()

    conn:attach('s1', {
      update = function() end,
      request = function()
        local known = async.Future.new()
        known:set_result({ outcome = { outcome = 'selected', optionId = 'allow' } })
        return known
      end,
    })
    agent:push(fake_agent.permission('s1', 'Bash'))

    eq('allow', agent:selected())
  end)

  it('answers requests no listener handles with method-not-found', function()
    local conn, agent = connected()

    conn:attach('s1', { update = function() end, request = function() end })
    agent:push(jsonrpc.request('fs-1', 'fs/read_text_file', { sessionId = 's1', path = '/x' }))
    agent:push(jsonrpc.request('fs-2', 'fs/read_text_file', { sessionId = 'nobody', path = '/x' }))

    for _, id in ipairs({ 'fs-1', 'fs-2' }) do
      local reply = agent:find(function(message)
        return message.id == id
      end)

      eq(jsonrpc.METHOD_NOT_FOUND, reply.error.code)
    end
  end)

  it('fails a request the agent answers with an error', function()
    local conn = connected({
      ['session/new'] = function(message)
        return { jsonrpc.error(message.id, jsonrpc.INTERNAL_ERROR, 'not logged in') }
      end,
    })

    local ok, err = pcall(run, function()
      conn:new_session({ cwd = '/w' })
    end)

    eq(false, ok)
    assert.is_truthy(tostring(err):find('not logged in', 1, true))
  end)

  it('introduces itself, and says how to sign in when the agent needs it', function()
    local conn, agent = connected({
      initialize = function(message)
        return {
          jsonrpc.result(message.id, {
            protocolVersion = 1,
            agentCapabilities = {},
            agentInfo = { name = 'claude', title = 'Claude' },
            authMethods = { { id = 'login', name = 'Log in with Claude' } },
          }),
        }
      end,
      ['session/new'] = function(message)
        return { jsonrpc.error(message.id, Connection.AUTH_REQUIRED, 'Authentication required') }
      end,
    })

    eq(Connection.CLIENT_INFO, agent.sent[1].params.clientInfo)

    local ok, err = pcall(run, function()
      conn:new_session({ cwd = '/w' })
    end)

    eq(false, ok)
    eq('Claude needs you to sign in (Log in with Claude): Authentication required', err)
  end)

  it('forks a session, at a message when given one, only when the agent can', function()
    local caps = { protocolVersion = 1, agentCapabilities = { sessionCapabilities = { fork = {} } } }
    local conn, agent = connected({
      initialize = function(message)
        return { jsonrpc.result(message.id, caps) }
      end,
    })

    run(function()
      conn:fork_session('s1', { cwd = '/w', message_id = 'm7' })
      conn:fork_session('s1', { cwd = '/w' })
    end)

    local forks = vim.tbl_filter(function(message)
      return message.method == 'session/fork'
    end, agent.sent)

    eq({ version = 1, messageId = 'm7' }, forks[1].params._meta.jetbrains.air.fork)
    eq(nil, forks[2].params._meta)

    local plain = connected()
    local ok, err = pcall(run, function()
      plain:fork_session('s1', { cwd = '/w' })
    end)

    eq({ false, 'this agent cannot fork sessions' }, { ok, err })
  end)

  it('refuses to load a session the agent cannot load', function()
    local conn = connected({
      initialize = function(message)
        return { jsonrpc.result(message.id, { protocolVersion = 1, agentCapabilities = {} }) }
      end,
    })

    local ok, err = pcall(run, function()
      conn:load_session('s1', { cwd = '/w' })
    end)

    eq(false, ok)
    eq('this agent cannot load stored sessions', err)
  end)

  it('fails pending requests and tells listeners when the agent exits', function()
    local conn, agent = connected({
      ['session/prompt'] = function()
        return {}
      end,
    })
    local reason

    conn:attach('s1', {
      update = function() end,
      close = function(why)
        reason = why
      end,
    })

    local task = async.run(function()
      return conn:prompt('s1', {})
    end)

    vim.wait(100, function()
      return agent:sent_method('session/prompt') ~= nil
    end)
    agent:exit(1)

    local ok, err = pcall(task.wait, task)

    eq(false, ok)
    eq('agent exited with code 1', err)
    eq('agent exited with code 1', reason)
    eq(true, conn.closed)
  end)

  it('closes a session only when the agent supports it', function()
    local conn, agent = connected()

    run(function()
      conn:close_session('s1')
    end)

    eq('s1', agent:sent_method('session/close').params.sessionId)

    conn.capabilities = {}
    run(function()
      conn:close_session('s2')
    end)

    eq(1, agent:count('session/close'))
  end)

  describe('permission_outcome', function()
    local options = {
      { optionId = 'allow', kind = 'allow_once' },
      { optionId = 'always', kind = 'allow_always' },
      { optionId = 'reject', kind = 'reject_once' },
    }

    it('picks the option of the exact kind, then of the same family', function()
      eq({ outcome = 'selected', optionId = 'always' }, Connection.permission_outcome(options, 'allow_always'))
      eq({ outcome = 'selected', optionId = 'allow' }, Connection.permission_outcome(options, true))
      eq({ outcome = 'selected', optionId = 'reject' }, Connection.permission_outcome(options, 'reject_always'))
    end)

    it('cancels when nothing fits', function()
      eq({ outcome = 'cancelled' }, Connection.permission_outcome(options, 'cancelled'))
      eq({ outcome = 'cancelled' }, Connection.permission_outcome({}, 'allow_once'))
      eq({ outcome = 'cancelled' }, Connection.permission_outcome(options, nil))
    end)
  end)

  it('tells the agent it can follow sub-agent sessions', function()
    local fake = require('harness.fake_agent').new()
    local connection = Connection(fake)

    require('harness.async')
      .run(function()
        connection:initialize()
      end)
      :wait()

    eq('table', type(fake:sent_method('initialize').params.clientCapabilities.subagents))
  end)
end)

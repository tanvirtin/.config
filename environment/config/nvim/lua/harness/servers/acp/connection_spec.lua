local Connection = require('harness.servers.acp.connection')
local async = require('harness.async')
local fake_agent = require('harness.servers.acp.fake_agent')
local jsonrpc = require('harness.servers.acp.jsonrpc')

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
    event = function(event)
      log[#log + 1] = event.kind
    end,
  }
end

describe('harness.servers.acp.connection:', function()
  it('initializes and keeps the agent\'s capabilities', function()
    local conn = connected()

    eq(true, conn.agent_capabilities.loadSession)
    eq(true, conn:capabilities().load)
    eq(true, conn:capabilities().list)
    eq(false, conn:capabilities().fork)
    eq(true, conn:supports('list'))
    eq(false, conn:supports('fork'))
  end)

  it('routes each session\'s updates to its listener', function()
    local conn, agent = connected()
    local one, two = {}, {}

    conn:attach('s1', listener(one))
    conn:attach('s2', listener(two))
    agent:push(fake_agent.chunk('s1', 'a'), fake_agent.chunk('s2', 'b'), fake_agent.chunk('s1', 'c'))

    eq({ 'message', 'message' }, one)
    eq({ 'message' }, two)
  end)

  it('keeps updates that arrive before a session is attached', function()
    local conn, agent = connected()
    local seen = {}

    agent:push(fake_agent.update('s9', { sessionUpdate = 'available_commands_update' }))
    conn:attach('s9', listener(seen))

    eq({ 'commands' }, seen)
  end)

  it('creates and prompts a session', function()
    local conn, agent = connected()

    local result = run(function()
      local id = conn:new_session({ cwd = '/w', mcp_servers = {}, system_prompt = 'be brief' }).id
      return conn:prompt(id, require('harness.types.content').prompt('hi'))
    end)

    local new = agent:sent_method('session/new')

    eq('end_turn', result)
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

    eq({ 'user' }, seen)
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

    eq({ { id = 'a' }, { id = 'b' } }, sessions)
    eq(2, pages)
  end)

  it('keeps listing past 200 sessions', function()
    local conn = connected({
      ['session/list'] = function(message)
        local page = {}
        local cursor = message.params.cursor

        for i = 1, 100 do
          page[#page + 1] = { sessionId = 's' .. ((cursor or 0) + i) }
        end

        if not cursor then return { jsonrpc.result(message.id, { sessions = page, nextCursor = 100 }) } end
        if cursor == 100 then return { jsonrpc.result(message.id, { sessions = page, nextCursor = 200 }) } end
        if cursor == 200 then return { jsonrpc.result(message.id, { sessions = page, nextCursor = 300 }) } end

        return { jsonrpc.result(message.id, { sessions = {} }) }
      end,
    })

    local sessions = run(function()
      return conn:list_sessions('/w')
    end)

    eq(300, #sessions)
  end)

  it('stops paginating when a page is empty, even with a cursor', function()
    local pages = 0
    local conn = connected({
      ['session/list'] = function(message)
        pages = pages + 1
        return { jsonrpc.result(message.id, { sessions = {}, nextCursor = 'never' }) }
      end,
    })

    local sessions = run(function()
      return conn:list_sessions('/w')
    end)

    eq({}, sessions)
    eq(1, pages)
  end)

  it('answers a permission request with what the listener decides, even later', function()
    local conn, agent = connected()
    local answer = async.Future.new()

    local asked

    conn:attach('s1', {
      permission = function(request)
        asked = request
        return answer
      end,
    })
    agent:push(fake_agent.permission('s1', 'Bash'))

    eq(nil, agent:selected())
    eq('Bash', asked.tool)
    eq(
      { 'allow_once', 'allow_always', 'reject_once' },
      vim.tbl_map(function(choice)
        return choice.kind
      end, asked.choices)
    )

    answer:set_result('allow_once')
    async.drain()

    eq('allow', agent:selected())
  end)

  it('sends an answer that is already known at once', function()
    local conn, agent = connected()

    conn:attach('s1', {
      permission = function()
        return 'allow_once'
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

    local ok, err = run(function()
      return conn:new_session({ cwd = '/w' })
    end)

    eq(nil, ok)
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
            authMethods = {
              { id = 'login', name = 'Log in with Claude', description = 'Run `claude /login` in the terminal' },
            },
          }),
        }
      end,
      ['session/new'] = function(message)
        return { jsonrpc.error(message.id, Connection.AUTH_REQUIRED, 'Authentication required') }
      end,
    })

    eq(Connection.CLIENT_INFO, agent.sent[1].params.clientInfo)

    local ok, err = run(function()
      return conn:new_session({ cwd = '/w' })
    end)

    eq(nil, ok)
    eq(
      'Claude needs you to sign in: Run `claude /login` in the terminal, then send again (Authentication required)',
      err
    )
  end)

  it('falls back to the agent\'s own sign-in hint when it lists no way to sign in', function()
    local conn = connected({
      initialize = function(message)
        return {
          jsonrpc.result(message.id, { protocolVersion = 1, agentCapabilities = {}, agentInfo = { title = 'Claude' } }),
        }
      end,
      ['session/prompt'] = function(message)
        return { jsonrpc.error(message.id, Connection.AUTH_REQUIRED, 'Authentication required') }
      end,
    })

    conn.login = 'run `claude auth login` in a terminal'

    local _, err = run(function()
      return conn:prompt('s1', {})
    end)

    eq(
      'Claude needs you to sign in: run `claude auth login` in a terminal, then send again (Authentication required)',
      err
    )

    conn.login = nil

    _, err = run(function()
      return conn:prompt('s1', {})
    end)

    eq('Claude needs you to sign in: Authentication required', err)
  end)

  it('sends a system prompt only to an agent that takes one', function()
    local conn, agent = connected({
      initialize = function(message)
        return { jsonrpc.result(message.id, { protocolVersion = 1, agentCapabilities = {} }) }
      end,
    })

    run(function()
      conn:new_session({ cwd = '/w', system_prompt = 'be brief' })
    end)

    eq(nil, agent:sent_method('session/new').params.systemPrompt)
  end)

  it('forks a session, at a message when given one and the agent forks at messages, only when it can', function()
    local caps = { protocolVersion = 1, agentCapabilities = { sessionCapabilities = { fork = {} } } }
    local conn, agent = connected({
      initialize = function(message)
        return { jsonrpc.result(message.id, caps) }
      end,
    })

    run(function()
      conn:fork_session('s1', { cwd = '/w', message_id = 'm7' })
      conn.fork_at_message = true
      conn:fork_session('s1', { cwd = '/w', message_id = 'm7' })
      conn:fork_session('s1', { cwd = '/w' })
    end)

    local forks = vim.tbl_filter(function(message)
      return message.method == 'session/fork'
    end, agent.sent)

    eq(nil, forks[1].params._meta)
    eq({ version = 1, messageId = 'm7' }, forks[2].params._meta.jetbrains.air.fork)
    eq(nil, forks[3].params._meta)

    local plain = connected()
    local ok, err = run(function()
      return plain:fork_session('s1', { cwd = '/w' })
    end)

    eq({ nil, 'this agent cannot fork sessions' }, { ok, err })
  end)

  it('stops listing when the agent hands back a cursor it already gave', function()
    local calls = 0
    local conn = connected({
      ['session/list'] = function(message)
        calls = calls + 1
        return { jsonrpc.result(message.id, { sessions = { { sessionId = 's' .. calls } }, nextCursor = 'again' }) }
      end,
    })

    local listed = run(function()
      return conn:list_sessions('/w')
    end)

    eq(2, calls)
    eq({ { id = 's1' }, { id = 's2' } }, listed)
  end)

  it('refuses to load a session the agent cannot load', function()
    local conn = connected({
      initialize = function(message)
        return { jsonrpc.result(message.id, { protocolVersion = 1, agentCapabilities = {} }) }
      end,
    })

    local ok, err = run(function()
      return conn:load_session('s1', { cwd = '/w' })
    end)

    eq(nil, ok)
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

    local ok, err = task:wait()

    eq(nil, ok)
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

    conn.agent_capabilities = {}
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
    local fake = require('harness.servers.acp.fake_agent').new()
    local connection = Connection(fake)

    require('harness.async')
      .run(function()
        connection:initialize()
      end)
      :wait()

    eq('table', type(fake:sent_method('initialize').params.clientCapabilities.subagents))
  end)
end)

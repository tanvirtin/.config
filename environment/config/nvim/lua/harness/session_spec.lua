local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local async = require('harness.async')
local fake_agent = require('harness.fake_agent')
local jsonrpc = require('harness.acp.jsonrpc')

local eq = assert.are.same

local function session_with(script, approve)
  local agent = fake_agent.new(script)
  local conn = Connection(agent)
  local session = Session({ key = 'h1', id = 's1', dir = '/w', connection = conn, approve = approve }):attach()

  return session, agent
end

local function kinds(history)
  return vim.tbl_map(function(event)
    return event.kind
  end, history)
end

local function asking(tool)
  local prompt_id

  return {
    ['session/prompt'] = function(message)
      prompt_id = message.id
      return { fake_agent.permission('s1', tool) }
    end,
    reply = function(message)
      if message.id ~= 'perm-1' then return {} end

      return { fake_agent.chunk('s1', 'done'), jsonrpc.result(prompt_id, { stopReason = 'end_turn' }) }
    end,
  }
end

describe('harness.session:', function()
  it('runs a turn, joining the reply and recording the history', function()
    local session = session_with({
      ['session/prompt'] = function(message)
        return {
          fake_agent.chunk('s1', 'hello '),
          fake_agent.chunk('s1', 'world'),
          jsonrpc.result(message.id, { stopReason = 'end_turn' }),
        }
      end,
    })

    local result = session:prompt('hi'):wait()

    eq('hello world', result.text)
    eq('end_turn', result.stop_reason)
    eq({ 'prompt', 'message', 'stop' }, kinds(session.history))
    eq('hello world', session.history[2].text)
    eq('idle', session.state)
  end)

  it('sends the context block ahead of the prompt', function()
    local session, agent = session_with()

    session:prompt('hi', '<editor-context>here</editor-context>'):wait()

    eq({
      { type = 'text', text = '<editor-context>here</editor-context>' },
      { type = 'text', text = 'hi' },
    }, agent:sent_method('session/prompt').params.prompt)
    eq('hi', session.history[1].text)
  end)

  it('tells subscribers about each event until they unsubscribe', function()
    local session = session_with()
    local seen = {}
    local unsubscribe = session:subscribe(function(event, s)
      seen[#seen + 1] = event.kind .. '@' .. s.key
    end)

    session:prompt('one'):wait()
    unsubscribe()
    session:prompt('two'):wait()

    eq({ 'prompt@h1', 'message@h1', 'stop@h1' }, seen)
  end)

  it('refuses a second prompt while a turn runs', function()
    local session = session_with({
      ['session/prompt'] = function()
        return {}
      end,
    })

    session:prompt('one')

    local ok, err = pcall(session.prompt, session, 'two')

    eq(false, ok)
    assert.is_truthy(tostring(err):find('already running', 1, true))
  end)

  it('cancels the running turn', function()
    local prompt_id
    local session, agent = session_with({
      ['session/prompt'] = function(message)
        prompt_id = message.id
        return {}
      end,
      ['session/cancel'] = function()
        return { jsonrpc.result(prompt_id, { stopReason = 'cancelled' }) }
      end,
    })
    local task = session:prompt('long')

    vim.wait(1000, function()
      return prompt_id ~= nil
    end)
    session:cancel()

    eq('cancelled', task:wait().stop_reason)
    eq('s1', agent:sent_method('session/cancel').params.sessionId)
  end)

  it('asks approve for permissions and answers with the matching option', function()
    local asked
    local session, agent = session_with(asking('Bash'), function(request)
      asked = request
      return 'allow_always'
    end)

    local result = session:prompt('hi'):wait()

    eq('Bash', asked.tool)
    eq(session, asked.session)
    eq('always', agent:selected())
    eq({ { tool = 'Bash', allowed = true } }, result.permissions)
    eq({ kind = 'permission', tool = 'Bash', allowed = true }, session.history[2])
  end)

  it('waits for an approve that answers later', function()
    local answer = async.Future.new()
    local session, agent = session_with(asking('Bash'), function()
      return answer
    end)
    local task = session:prompt('hi')

    vim.wait(50, function()
      return false
    end)
    eq(false, task.done)

    answer:set_result('reject_once')
    async.drain()

    eq({ { tool = 'Bash', allowed = false } }, task:wait().permissions)
    eq('reject', agent:selected())
  end)

  it('rejects when approve fails', function()
    local session, agent = session_with(asking('Bash'), function()
      error('boom')
    end)

    session:prompt('hi'):wait()

    eq('reject', agent:selected())
  end)

  it('names tool updates after their tool call', function()
    local session = session_with({
      ['session/prompt'] = function(message)
        return {
          fake_agent.update('s1', {
            sessionUpdate = 'tool_call',
            toolCallId = 't1',
            title = 'Read',
            _meta = { claudeCode = { toolName = 'Read' } },
          }),
          fake_agent.update('s1', { sessionUpdate = 'tool_call_update', toolCallId = 't1', status = 'completed' }),
          jsonrpc.result(message.id, { stopReason = 'end_turn' }),
        }
      end,
    })

    session:prompt('hi'):wait()

    eq('Read', session.history[3].name)
  end)

  it('records a failed turn and fails its task', function()
    local session = session_with({
      ['session/prompt'] = function(message)
        return { jsonrpc.error(message.id, jsonrpc.INTERNAL_ERROR, 'not logged in') }
      end,
    })

    local ok, err = pcall(function()
      return session:prompt('hi'):wait()
    end)

    eq(false, ok)
    assert.is_truthy(tostring(err):find('not logged in', 1, true))
    eq({ kind = 'error', message = 'not logged in' }, session.history[2])
    eq('idle', session.state)
  end)

  it('closes when the agent exits, and says so', function()
    local session, agent = session_with()

    agent:exit(1)

    eq('closed', session.state)
    eq({ kind = 'error', message = 'agent exited with code 1' }, session.history[1])

    local ok = pcall(session.prompt, session, 'hi')
    eq(false, ok)
  end)

  it('keeps the title the agent gives it', function()
    local session, agent = session_with()

    agent:push(fake_agent.update('s1', { sessionUpdate = 'session_info_update', title = 'Rename x' }))

    eq('Rename x', session.title)
  end)
end)

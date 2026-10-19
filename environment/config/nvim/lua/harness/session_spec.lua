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

  describe('queue and interrupt', function()
    local function held()
      local ids = {}

      return ids,
        {
          ['session/prompt'] = function(message)
            ids[#ids + 1] = message.id
            return {}
          end,
        }
    end

    local function finish(agent, id, reason)
      agent:push(jsonrpc.result(id, { stopReason = reason or 'end_turn' }))
    end

    local function prompt_texts(agent)
      local out = {}

      for _, message in ipairs(agent.sent) do
        if message.method == 'session/prompt' then out[#out + 1] = message.params.prompt[1].text end
      end

      return out
    end

    it('queues while a turn runs, and sends the next one when the turn ends', function()
      local ids, script = held()
      local session, agent = session_with(script)

      session:prompt('first')
      vim.wait(500, function()
        return #ids == 1
      end)
      session:enqueue('second')
      session:enqueue('third')

      eq({ 'second', 'third' }, session:queued())
      eq({ 'first' }, prompt_texts(agent))

      finish(agent, ids[1])
      vim.wait(500, function()
        return #ids == 2
      end)

      eq({ 'first', 'second' }, prompt_texts(agent))
      eq({ 'third' }, session:queued())
    end)

    it('sends right away when queued while idle', function()
      local session, agent = session_with()

      session:enqueue('now')
      vim.wait(500, function()
        return #prompt_texts(agent) == 1
      end)

      eq({ 'now' }, prompt_texts(agent))
      eq({}, session:queued())
    end)

    it('hands back what was queued on interrupt, and sends nothing after the cancelled turn', function()
      local ids, script = held()

      script['session/cancel'] = function()
        return { jsonrpc.result(ids[1], { stopReason = 'cancelled' }) }
      end

      local session, agent = session_with(script)
      local notified = 0

      session:subscribe(function(event)
        if event.kind == 'queue' then notified = notified + 1 end
      end)
      session:prompt('first')
      vim.wait(500, function()
        return #ids == 1
      end)
      session:enqueue('second')

      eq({ 'second' }, session:cancel())
      vim.wait(200)

      eq({}, session:queued())
      eq({ 'first' }, prompt_texts(agent))
      eq(true, notified >= 2)
      eq(
        false,
        vim.tbl_contains(
          vim.tbl_map(function(event)
            return event.kind
          end, session.history),
          'queue'
        )
      )
    end)

    it('answers an open permission request with cancelled on interrupt, and closes its prompt', function()
      local dismissed = false
      local prompt_id
      local session, agent = session_with({
        ['session/prompt'] = function(message)
          prompt_id = message.id
          return { fake_agent.permission('s1', 'Edit') }
        end,
      }, function()
        local answer = async.Future.new()
        answer.dismiss = function()
          dismissed = true
        end
        return answer
      end)

      session:prompt('edit it')
      vim.wait(500, function()
        return prompt_id ~= nil and next(session._pending) ~= nil
      end)
      session:cancel()

      local function reply()
        return agent:find(function(message)
          return message.id == 'perm-1' and message.result ~= nil
        end)
      end

      vim.wait(500, function()
        return reply() ~= nil
      end)

      eq({ outcome = { outcome = 'cancelled' } }, reply().result)
      eq(true, dismissed)
      eq({ kind = 'permission', tool = 'Edit', allowed = false }, session.history[#session.history])
      eq(nil, next(session._pending))
    end)

    it('lists the permission requests it is waiting on, announcing when that changes', function()
      local answer = async.Future.new()
      local announced = 0
      local session = session_with({
        ['session/prompt'] = function()
          return { fake_agent.permission('s1', 'Edit') }
        end,
      }, function()
        return answer
      end)

      session:subscribe(function(event)
        if event.kind == 'waiting' then announced = announced + 1 end
      end)
      session:prompt('edit')
      vim.wait(500, function()
        return #session:waiting() == 1
      end)

      eq({ { tool = 'Edit', id = 't1', title = 'Edit' } }, session:waiting())

      answer:set_result('allow_once')
      async.drain()

      eq({}, session:waiting())
      eq(2, announced)
    end)

    it('steers the running turn when the agent supports it', function()
      local ids, script = held()

      script[Connection.STEER_METHOD] = function(message)
        return { jsonrpc.result(message.id, { outcome = 'injected' }) }
      end

      local session, agent = session_with(script)

      session.connection.extensions = { steering = { supported = true } }
      session:prompt('first')
      vim.wait(500, function()
        return #ids == 1
      end)

      local result = session:steer('look at b instead'):wait()
      local steer = agent:sent_method(Connection.STEER_METHOD)

      eq('injected', result.outcome)
      eq('look at b instead', steer.params.prompt[1].text)
      eq('promptRequired', steer.params._meta.steering.idleBehavior)
      eq({ kind = 'prompt', text = 'look at b instead' }, session.history[#session.history])
      eq({}, session:queued())
    end)

    it('queues instead of steering when the agent cannot steer', function()
      local ids, script = held()
      local session, agent = session_with(script)

      session:prompt('first')
      vim.wait(500, function()
        return #ids == 1
      end)

      assert.is_nil(session:steer('later please'))
      eq({ 'later please' }, session:queued())
      assert.is_nil(agent:sent_method(Connection.STEER_METHOD))
    end)

    it('sends a steer as a normal prompt when the turn ended first, recording it once', function()
      local session, agent = session_with({
        [Connection.STEER_METHOD] = function(message)
          return { jsonrpc.result(message.id, { outcome = 'promptRequired' }) }
        end,
      })

      session.connection.extensions = { steering = { supported = true } }
      session.state = 'running'

      local task = session:steer('follow up')

      session.state = 'idle'
      task:wait()
      vim.wait(500, function()
        return #prompt_texts(agent) == 1
      end)

      eq({ 'follow up' }, prompt_texts(agent))
      eq(1, #vim.tbl_filter(function(event)
        return event.kind == 'prompt'
      end, session.history))
    end)
  end)
end)

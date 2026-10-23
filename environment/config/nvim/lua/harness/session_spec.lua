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
  it('gives an agent with no system prompt its instructions with the first prompt that lands, once', function()
    local session, agent = session_with({
      ['session/prompt'] = fake_agent.replying('ok'),
    })

    session.agent = { system = 'be brief' }
    session:prompt('one'):wait()
    session:prompt('two'):wait()

    local prompts = vim.tbl_filter(function(message)
      return message.method == 'session/prompt'
    end, agent.sent)

    eq('<harness-instructions>be brief</harness-instructions>', prompts[1].params.prompt[1].text)
    eq('two', prompts[2].params.prompt[#prompts[2].params.prompt].text)
    eq(1, #prompts[2].params.prompt)

    local taking, sent = session_with({ ['session/prompt'] = fake_agent.replying('ok') })

    taking.agent = { system = 'be brief' }
    taking.connection.agent_capabilities = { sessionCapabilities = { systemPrompt = {} } }
    taking:prompt('one'):wait()

    eq(1, #sent:sent_method('session/prompt').params.prompt)
  end)

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
    eq({ kind = 'permission', tool = 'Bash', allowed = true, id = 't1' }, session.history[2])
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
      eq(
        { kind = 'permission', tool = 'Edit', allowed = false, id = 't1', cancelled = true },
        session.history[#session.history]
      )
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
      eq({ kind = 'prompt', text = 'look at b instead', steered = true }, session.history[#session.history])
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
      eq(nil, session.history[1].steered)
    end)
  end)

  describe('modes, options and commands', function()
    local OPTIONS = {
      {
        id = 'mode',
        category = 'mode',
        type = 'select',
        currentValue = 'default',
        options = {
          { value = 'default', name = 'Manual' },
          { value = 'acceptEdits', name = 'Accept edits' },
          { value = 'plan', name = 'Plan' },
        },
      },
      {
        id = 'model',
        category = 'model',
        type = 'select',
        currentValue = 'opus',
        options = { { group = 'g', name = 'Claude', options = { { value = 'opus', name = 'Opus' } } } },
      },
    }

    local function configured(script)
      local session, agent = session_with(script)

      session:configure({ configOptions = vim.deepcopy(OPTIONS) })

      return session, agent
    end

    it('reads the mode and model from config options, including grouped choices', function()
      local session = configured()

      eq({ id = 'default', name = 'Manual' }, session:mode())
      eq('Opus', session:choice('model').name)
      eq(3, #session:mode_choices())
    end)

    it('keeps option, mode and command updates as state, out of the history', function()
      local session, agent = configured()
      local seen = {}

      session:subscribe(function(event)
        seen[#seen + 1] = event.kind
      end)
      agent:push(fake_agent.update('s1', { sessionUpdate = 'current_mode_update', currentModeId = 'plan' }))
      agent:push(fake_agent.update('s1', {
        sessionUpdate = 'available_commands_update',
        availableCommands = { { name = 'review', description = 'review changes' } },
      }))

      eq('Plan', session:mode().name)
      eq('review', session.commands[1].name)
      eq({}, session.history)
      eq({ 'mode', 'commands' }, seen)
    end)

    it('sets an option through session/set_config_option and takes the options it returns', function()
      local returned = vim.deepcopy(OPTIONS)

      returned[1].currentValue = 'plan'

      local session, agent = configured({
        ['session/set_config_option'] = function(message)
          return { jsonrpc.result(message.id, { configOptions = returned }) }
        end,
      })

      session:set_mode('plan'):wait()

      local sent = agent:sent_method('session/set_config_option').params

      eq({ 'mode', 'plan' }, { sent.configId, sent.value })
      eq('Plan', session:mode().name)
    end)

    it('uses session/set_mode for agents that only have modes', function()
      local session, agent = session_with()

      session:configure({
        modes = {
          currentModeId = 'ask',
          availableModes = { { id = 'ask', name = 'Ask' }, { id = 'code', name = 'Code' } },
        },
      })
      session:cycle_mode():wait()

      eq('code', agent:sent_method('session/set_mode').params.modeId)
      eq('Code', session:mode().name)
    end)

    it('cycles through the modes, wrapping around', function()
      local session = configured()
      local seen = {}

      session.set_mode = function(_, id)
        seen[#seen + 1] = id
        for _, option in ipairs(session.options) do
          if option.id == 'mode' then option.currentValue = id end
        end
      end

      for _ = 1, 3 do
        session:cycle_mode()
      end

      eq({ 'acceptEdits', 'plan', 'default' }, seen)
    end)
  end)

  describe('sub-agents', function()
    local function spawn(agent)
      agent:push(
        fake_agent.update(
          's1',
          { sessionUpdate = 'subagent_update', sessionId = 'c1', title = 'Explore', state = { state = 'running' } }
        )
      )
    end

    it('follows a child session, filing its work under the tool call that started it', function()
      local session, agent = session_with()

      spawn(agent)
      agent:push(fake_agent.update('c1', { sessionUpdate = 'session_message', messageId = 'task1', content = {} }))
      agent:push(
        fake_agent.update(
          'c1',
          { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'two files' } }
        )
      )
      agent:push(fake_agent.update('s1', {
        sessionUpdate = 'subagent_update',
        sessionId = 'c1',
        state = { state = 'idle', stopReason = 'end_turn' },
      }))

      eq({ { kind = 'message', text = 'two files', parent = 'task1' } }, session.history)
      eq({ id = 'c1', tool = 'task1', title = 'Explore', state = 'idle', stop = 'end_turn' }, session.children.c1)
    end)

    it('takes the tool call from the child\'s own updates when it has no delegation message', function()
      local session, agent = session_with()

      spawn(agent)
      agent:push(fake_agent.update('c1', {
        sessionUpdate = 'tool_call',
        toolCallId = 'inner',
        title = 'ls',
        _meta = { claudeCode = { toolName = 'Bash', parentToolUseId = 'task1' } },
      }))
      agent:push(
        fake_agent.update('c1', { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'done' } })
      )

      eq('task1', session.history[1].parent)
      eq('task1', session.history[2].parent)
    end)

    it('asks the child\'s permission requests through the parent, and stops listening when closed', function()
      local asked
      local session, agent = session_with({}, function(request)
        asked = request.tool
        return 'allow_once'
      end)

      spawn(agent)
      agent:push(fake_agent.permission('c1', 'Bash', 'perm-c1'))

      eq('Bash', asked)
      eq(
        'allow',
        agent:find(function(message)
          return message.id == 'perm-c1' and message.result ~= nil
        end).result.outcome.optionId
      )

      session:close()
      agent:push(
        fake_agent.update('c1', { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'late' } })
      )
      eq(
        nil,
        vim.tbl_filter(function(event)
          return event.text == 'late'
        end, session.history)[1]
      )
    end)
  end)
end)

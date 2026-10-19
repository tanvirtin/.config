local events = require('harness.events')

local eq = assert.are.same

describe('harness.events:', function()
  describe('from_update', function()
    it('turns text chunks into message, thought and user events', function()
      local content = { type = 'text', text = 'hi' }

      eq(
        { kind = 'message', text = 'hi' },
        events.from_update({ sessionUpdate = 'agent_message_chunk', content = content })
      )
      eq(
        { kind = 'thought', text = 'hi' },
        events.from_update({ sessionUpdate = 'agent_thought_chunk', content = content })
      )
      eq(
        { kind = 'user', text = 'hi' },
        events.from_update({ sessionUpdate = 'user_message_chunk', content = content })
      )
    end)

    it('names tool calls from _meta and keeps their diffs', function()
      local event = events.from_update({
        sessionUpdate = 'tool_call',
        toolCallId = 't1',
        title = 'Edit a.lua',
        status = 'pending',
        _meta = { claudeCode = { toolName = 'Edit' } },
        content = {
          { type = 'diff', path = '/a.lua', oldText = 'a', newText = 'b' },
          { type = 'content', content = { type = 'text', text = 'x' } },
        },
      })

      eq('tool_call', event.kind)
      eq('t1', event.id)
      eq('Edit', event.name)
      eq({ { path = '/a.lua', old = 'a', new = 'b' } }, event.diffs)
    end)

    it('treats JSON nulls as missing: a new file has no old text', function()
      local event = events.from_update({
        sessionUpdate = 'tool_call',
        toolCallId = 't1',
        title = vim.NIL,
        status = vim.NIL,
        rawInput = vim.NIL,
        content = { { type = 'diff', path = '/new.lua', oldText = vim.NIL, newText = 'x = 1' } },
      })

      eq({ { path = '/new.lua', old = '', new = 'x = 1' } }, event.diffs)
      eq(nil, event.title)
      eq(nil, event.status)
      eq(nil, event.input)
    end)

    it('reads tool updates, plans, titles and usage', function()
      eq(
        'completed',
        events.from_update({ sessionUpdate = 'tool_call_update', toolCallId = 't1', status = 'completed' }).status
      )
      eq(
        { kind = 'plan', entries = { { content = 'a', status = 'completed' } } },
        events.from_update({
          sessionUpdate = 'plan',
          entries = { { content = 'a', status = 'completed', priority = 'high' } },
        })
      )
      eq(
        { kind = 'title', title = 'Fix it' },
        events.from_update({ sessionUpdate = 'session_info_update', title = 'Fix it' })
      )
      eq(
        { kind = 'usage', used = 5, size = 10 },
        events.from_update({ sessionUpdate = 'usage_update', used = 5, size = 10 })
      )
    end)

    it('keeps a tool\'s category, input, locations, and the output of a finished call', function()
      local running = events.from_update({
        sessionUpdate = 'tool_call_update',
        toolCallId = 't1',
        kind = 'execute',
        rawInput = { command = 'ls' },
        content = { { type = 'content', content = { type = 'text', text = 'List files' } } },
      })
      local done = events.from_update({
        sessionUpdate = 'tool_call_update',
        toolCallId = 't1',
        status = 'completed',
        locations = { { path = '/a.lua', line = 3 } },
        content = { { type = 'content', content = { type = 'text', text = '```console\na\nb\n```' } } },
      })

      eq('execute', running.category)
      eq({ command = 'ls' }, running.input)
      eq(nil, running.output)
      eq('a\nb', done.output)
      eq({ { path = '/a.lua', line = 3 } }, done.locations)
      eq(
        'raw',
        events.from_update({
          sessionUpdate = 'tool_call_update',
          toolCallId = 't1',
          status = 'failed',
          rawOutput = 'raw',
        }).output
      )
    end)

    it('reads the cost from usage', function()
      eq(
        { kind = 'usage', used = 5, size = 10, cost = 0.25 },
        events.from_update({ sessionUpdate = 'usage_update', used = 5, size = 10, cost = { amount = 0.25 } })
      )
    end)

    it('reads a tool name from any agent\'s _meta, and none when there is none', function()
      eq('shell', events.tool_name({ _meta = { codex = { toolName = 'shell' } } }))
      eq('Edit', events.tool_name({ _meta = { claudeCode = { toolName = 'Edit' } } }))
      eq(nil, events.tool_name({ title = 'Run ls' }))
      eq(nil, events.tool_name(nil))
    end)

    it('reads config options, the current mode and the agent\'s slash commands', function()
      eq(
        { kind = 'config', options = { { id = 'mode', currentValue = 'plan' } } },
        events.from_update({
          sessionUpdate = 'config_option_update',
          configOptions = { { id = 'mode', currentValue = 'plan' } },
        })
      )
      eq(
        { kind = 'mode', id = 'plan' },
        events.from_update({ sessionUpdate = 'current_mode_update', currentModeId = 'plan' })
      )
      eq(
        { kind = 'commands', commands = { { name = 'review', description = 'review changes', hint = 'branch' } } },
        events.from_update({
          sessionUpdate = 'available_commands_update',
          availableCommands = { { name = 'review', description = 'review changes', input = { hint = 'branch' } } },
        })
      )
    end)

    it('skips updates no view needs', function()
      eq(nil, events.from_update({ sessionUpdate = 'session_info_update', _meta = {} }))
      eq(nil, events.from_update({ sessionUpdate = 'agent_message_chunk', content = { type = 'image' } }))
      eq(nil, events.from_update(nil))
    end)
  end)

  describe('append', function()
    it('joins consecutive text of the same kind', function()
      local history = {}

      events.append(history, { kind = 'message', text = 'a' })
      events.append(history, { kind = 'message', text = 'b' })
      events.append(history, { kind = 'thought', text = 'c' })
      events.append(history, { kind = 'message', text = 'd' })

      eq({
        { kind = 'message', text = 'ab' },
        { kind = 'thought', text = 'c' },
        { kind = 'message', text = 'd' },
      }, history)
    end)

    it('keeps prompts apart and stores copies', function()
      local history = {}
      local prompt = events.prompt('one')

      events.append(history, prompt)
      events.append(history, events.prompt('two'))
      prompt.text = 'changed'

      eq({ events.prompt('one'), events.prompt('two') }, history)
    end)
  end)
end)

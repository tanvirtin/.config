local text_renderer = require('harness.transcript.text_renderer')
local events = require('harness.types.events')

local eq = assert.are.same

describe('harness.transcript.text_renderer:', function()
  it('renders a compact transcript for agents, without tool output', function()
    local lines = text_renderer.render({
      events.prompt('list it'),
      { kind = events.KIND.tool_call, id = 't1', name = 'Bash', category = 'execute', input = { command = 'ls' } },
      { kind = events.KIND.tool_update, id = 't1', status = 'completed', output = 'a\nb' },
      { kind = events.KIND.message, text = 'two files' },
    }, 'Listing')

    eq({ '# Listing', '', '> list it', '', '-> Bash ls', '', 'two files' }, lines)
  end)
end)

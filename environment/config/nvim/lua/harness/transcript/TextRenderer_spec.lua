local TextRenderer = require('harness.transcript.TextRenderer')
local events = require('harness.events')

local eq = assert.are.same

describe('harness.transcript.TextRenderer:', function()
  it('renders a compact transcript for agents, without tool output', function()
    local lines = TextRenderer.render({
      events.prompt('list it'),
      { kind = events.KIND.tool_call, id = 't1', name = 'Bash', category = 'execute', input = { command = 'ls' } },
      { kind = events.KIND.tool_update, id = 't1', status = 'completed', output = 'a\nb' },
      { kind = events.KIND.message, text = 'two files' },
    }, 'Listing')

    eq({ '# Listing', '', '> list it', '', '-> Bash ls', '', 'two files' }, lines)
  end)
end)

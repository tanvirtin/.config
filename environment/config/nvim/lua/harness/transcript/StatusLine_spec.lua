local StatusLine = require('harness.transcript.StatusLine')
local theme = require('harness.transcript.theme')

local eq = assert.are.same

local function text(line)
  return table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, line))
end

describe('harness.transcript.StatusLine:', function()
  it('shows nothing when idle with an empty queue', function()
    assert.is_nil(StatusLine.lines({ running = false }))
  end)

  it('lists queued prompts by their first line when idle', function()
    local lines = StatusLine.lines({ running = false, queue = { '  next thing\nmore' } })

    eq(2, #lines)
    eq('  ' .. theme.QUEUE_ICON .. 'queued next thing', text(lines[2]))
  end)

  it('shows a spinner, the label and the elapsed time while working', function()
    local lines = StatusLine.lines({ running = true, frame = 2, started = 0, label = 'Thinking' }, 5000)

    eq(theme.SPINNER[2] .. ' Thinking · 5s · <C-c> interrupt', text(lines[2]))
  end)

  it('says a session is loading while the agent replays it, above prompts waiting for it', function()
    local lines = StatusLine.lines({ running = false, loading = true, frame = 1, queue = { 'next' } })

    eq(3, #lines)
    eq(theme.SPINNER[1] .. ' loading · the agent is replaying this session', text(lines[2]))
    eq('  ' .. theme.QUEUE_ICON .. 'queued next', text(lines[3]))
  end)

  it('asks about the first permission with its choices, counting the rest', function()
    local lines = StatusLine.lines({
      running = true,
      asks = { { text = 'Bash ls' }, { text = 'Edit' } },
      choices = { { key = '1', label = 'Allow once' } },
      queue = { 'later' },
    })

    eq(theme.WAITING_ICON[1] .. 'Allow Bash ls?  (+1 more)', text(lines[2]))
    eq('   1 Allow once   <C-c> interrupt', text(lines[3]))
    eq(4, #lines)
  end)

  it('points at a request answered elsewhere', function()
    local lines = StatusLine.lines({ running = true, waiting = { { title = 'Write a.lua' } } })

    assert.truthy(text(lines[2]):find('waiting for you: Write a.lua', 1, true))
  end)
end)

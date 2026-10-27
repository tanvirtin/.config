local status_line = require('harness.transcript.status_line')
local theme = require('harness.transcript.theme')

local eq = assert.are.same

local function text(line)
  return table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, line))
end

describe('harness.transcript.status_line:', function()
  it('shows nothing when idle with an empty queue', function()
    assert.is_nil(status_line.lines({ running = false }))
  end)

  it('lists queued prompts by their first line when idle', function()
    local lines = status_line.lines({ running = false, queue = { '  next thing\nmore' } })

    eq(2, #lines)
    eq('  ' .. theme.QUEUE_ICON .. 'queued next thing', text(lines[2]))
  end)

  it('shows the running icon, a pulsing label and the elapsed time while working', function()
    local lines = status_line.lines({ running = true, started = 0, label = 'Thinking' }, 5000)

    eq(theme.RUNNING_ICON .. 'Thinking · 5s · <C-c> interrupt', text(lines[2]))
  end)

  it('cycles working words when no label is given', function()
    local first = status_line.lines({ running = true, started = 0 }, 0)
    local second = status_line.lines({ running = true, started = 0 }, 3000)

    assert.truthy(text(first[2]):find(theme.working_word(0, 0), 1, true))
    assert.truthy(text(second[2]):find(theme.working_word(3000, 0), 1, true))
    eq('UiWorking2', second[2][2][2])
  end)

  it('pulses the running icon', function()
    local first = status_line.lines({ running = true, started = 0 }, 0)
    local second = status_line.lines({ running = true, started = 0 }, 300)

    eq('UiPulse1', first[2][1][2])
    eq('UiPulse2', second[2][1][2])
  end)

  it('says a session is loading while the agent replays it, above prompts waiting for it', function()
    local lines = status_line.lines({ running = false, loading = true, queue = { 'next' } })

    eq(3, #lines)
    eq(theme.motion('loading') .. ' loading · the agent is replaying this session', text(lines[2]))
    eq('  ' .. theme.QUEUE_ICON .. 'queued next', text(lines[3]))
  end)

  it('asks about the first permission with its choices, counting the rest', function()
    local lines = status_line.lines({
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
    local lines = status_line.lines({ running = true, waiting = { { title = 'Write a.lua' } } })

    assert.truthy(text(lines[2]):find('waiting for you: Write a.lua', 1, true))
  end)
end)

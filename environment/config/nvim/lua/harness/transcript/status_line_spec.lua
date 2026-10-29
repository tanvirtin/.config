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

  describe('a question from the agent', function()
    local translate = require('harness.servers.acp.translate')
    local fake_agent = require('harness.servers.acp.fake_agent')
    local ElicitationPrompt = require('harness.ui.ElicitationPrompt')

    local function prompt_for(params)
      return ElicitationPrompt({ request = assert(translate.elicitation_request(params)), session = {} })
    end

    local function texts(lines)
      return vim.tbl_map(text, lines)
    end

    it('lists its choices one per line with their notes, then how to decline', function()
      local lines = status_line.lines({ running = true, asks = { prompt_for(fake_agent.QUESTION), {} } })

      eq({
        '',
        theme.WAITING_ICON[1] .. 'Which database?  (+1 more)',
        '   Database',
        '   1 Postgres  relational',
        '   2 Redis',
        '   3 Other…',
        '   4 Skip',
        '   0 decline   <C-c> interrupt',
      }, texts(lines))
    end)

    it('shows the step and the question of a form with several, with boxes for a multi-select', function()
      local prompt = prompt_for({
        mode = 'form',
        message = 'Please answer the following questions.',
        requestedSchema = {
          properties = {
            question_0 = {
              type = 'array',
              title = 'Tools',
              description = 'Which tools?',
              items = { enum = { 'a', 'b' } },
            },
            question_1 = { type = 'string', enum = { 'x' } },
          },
        },
      })

      prompt:answer('2')

      local shown = texts(status_line.lines({ running = true, asks = { prompt } }))

      eq(theme.WAITING_ICON[1] .. 'Please answer the following questions.  1/2', shown[2])
      eq('   Tools: Which tools?', shown[3])
      eq({ '   1 [ ] a', '   2 [x] b', '   3 Done' }, { shown[4], shown[5], shown[6] })
    end)

    it('says where to write while an answer is being written, and shows what was wrong', function()
      local prompt = prompt_for({
        mode = 'form',
        message = 'Age?',
        requestedSchema = { properties = { age = { type = 'integer', title = 'Age' } } },
      })

      prompt:answer('1')

      local writing = texts(status_line.lines({ running = true, asks = { prompt } }))

      eq({ '   Age', '   write Age in the composer, or close it to go back' }, { writing[3], writing[4] })

      prompt:stop_writing()
      prompt.error = 'write a number'

      local shown = texts(status_line.lines({ running = true, asks = { prompt } }))

      eq('   write a number', shown[#shown - 1])
    end)

    it('asks even when no turn is running, as a sign-in link arrives on its own', function()
      local prompt = prompt_for({ mode = 'url', message = 'Sign in to linear', url = 'https://x', elicitationId = 'e' })

      eq({
        '',
        theme.WAITING_ICON[1] .. 'Sign in to linear',
        '   https://x',
        '   1 Open in the browser',
        '   0 decline   <C-c> interrupt',
        '  ' .. theme.QUEUE_ICON .. 'queued later',
      }, texts(status_line.lines({ running = false, asks = { prompt }, queue = { 'later' } })))
    end)
  end)

  it('points at a request answered elsewhere', function()
    local lines = status_line.lines({ running = true, waiting = { { title = 'Write a.lua' } } })

    assert.truthy(text(lines[2]):find('waiting for you: Write a.lua', 1, true))
  end)
end)

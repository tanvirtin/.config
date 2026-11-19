local Tile = require('ui.pixel.Tile')
local graphics = require('core.editor.graphics')
local ticker = require('ui.pixel.ticker')
local indicators = require('ui.pixel.indicators')
local theme = require('sn.transcript.theme')
local status_line = require('sn.transcript.status_line')

local eq = assert.are.same

local function text(line)
  return table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, line))
end

local function working(...)
  return text(theme.working(...))
end

describe('sn.transcript.status_line:', function()
  it('shows nothing when idle with an empty queue', function()
    assert.is_nil(status_line.lines({ running = false }))
  end)

  it('lists queued prompts by their first line when idle', function()
    local lines = status_line.lines({ running = false, queue = { '  next thing\nmore' } })

    eq(2, #lines)
    eq('  ' .. theme.QUEUE_ICON[1] .. 'queued next thing', text(lines[2]))
  end)

  it('says a queued message is waiting for a free turn when the session is held', function()
    local lines = status_line.lines({ running = false, held = true, queue = { 'next' } })

    eq(theme.WAITING_ICON[1] .. 'waiting for a free turn: other sessions are running (max_running)', text(lines[2]))
    eq('  ' .. theme.QUEUE_ICON[1] .. 'queued next', text(lines[3]))
  end)

  it('shows the working animation, then the elapsed time while working', function()
    local lines = status_line.lines({ running = true, started = 0, label = 'Thinking' }, 5000)

    eq(' ' .. working(5000, 0) .. ' · 5s · <C-c> interrupt', text(lines[2]))
  end)

  it('turns the running icon a glyph per step, in the accent', function()
    local first = status_line.lines({ running = true, started = 0 }, 0)
    local second = status_line.lines({ running = true, started = 0 }, 100)

    eq({ '⠋', 'UiAccent' }, first[2][2])
    eq({ '⠙', 'UiAccent' }, second[2][2])
  end)

  it('says a session is loading while the agent replays it, above prompts waiting for it', function()
    local lines = status_line.lines({ running = false, loading = true, queue = { 'next' } })

    local snow = require('sn.transcript.status_line.replay').SNOW_ROWS

    eq(3 + snow, #lines)
    eq('⡇ loading · the agent is replaying this session', text(lines[2]))
    assert.is_truthy(text(lines[3]):find('[░▒▓]'))
    eq('  ' .. theme.QUEUE_ICON[1] .. 'queued next', text(lines[#lines]))
  end)

  it('shows no static under the loading line while motion is reduced', function()
    local settings = require('sn.settings.theme')
    local motion = settings:get('motion')

    settings:assign({ motion = vim.tbl_extend('force', motion, { reduced = true }) })

    local lines = status_line.lines({ running = false, loading = true, queue = {} })

    settings:assign({ motion = motion })

    eq(2, #lines)
  end)

  it('asks about the first permission with its choices, counting the rest', function()
    local lines = status_line.lines({
      running = true,
      asks = { { text = 'Bash ls' }, { text = 'Edit' } },
      choices = { { key = '1', label = 'Allow once' } },
      queue = { 'later' },
    })

    eq('▎' .. theme.WAITING_ICON[1] .. 'Allow Bash ls?  (+1 more)', text(lines[2]))
    eq('▎  1 Allow once', text(lines[3]))
    eq('▎  <C-c> interrupt', text(lines[4]))
    eq(5, #lines)
  end)

  it('draws a permission as a warn card: a rail, a surface behind every chunk and rows padded to the width', function()
    local lines = status_line.lines({
      running = true,
      width = 30,
      asks = { { text = 'Bash ls', choices = { { key = '1', label = 'Allow' } } } },
    })

    eq({ '▎', { 'UiRailWarn', 'UiSurfaceWarn' } }, lines[2][1])
    eq({ '1', { 'UiAccent', 'UiSurfaceRaised' } }, lines[3][2])

    for i = 2, #lines do
      eq(30, vim.fn.strdisplaywidth(text(lines[i])))
    end
  end)

  describe('with pixels for the rail', function()
    local original

    before_each(function()
      original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
      graphics.upload = function() end
      graphics.delete = function() end
    end)

    after_each(function()
      indicators.stop()
      ticker.stop()
      Tile.drain()
      Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
    end)

    it('starts each card row with a pixel rail one cell wide, and keeps every row the same width', function()
      local state = {
        running = true,
        width = 30,
        asks = { { text = 'Bash ls', choices = { { key = '1', label = 'Allow' } } } },
      }
      local plain = status_line.card_of(status_line.lines(state, 0))

      Tile.available = function()
        return true
      end

      local pixel = status_line.card_of(status_line.lines(state, 0))

      eq(#plain, #pixel)
      assert.is_true(#pixel > 0)

      for index, row in ipairs(pixel) do
        eq(indicators.chunk('rail', 'warn', index, #pixel), row[1])
        eq(vim.fn.strdisplaywidth(text(plain[index])), vim.fn.strdisplaywidth(text(row)))
        eq(30, vim.fn.strdisplaywidth(text(row)))
      end
    end)
  end)

  describe('with pixels for the mascot', function()
    local original
    local mascot = require('sn.transcript.mascot')

    before_each(function()
      original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
      graphics.upload = function() end
      graphics.delete = function() end

      Tile.available = function()
        return true
      end
    end)

    after_each(function()
      mascot.stop()
      ticker.stop()
      Tile.drain()
      Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
    end)

    it('keeps dissolving through the wane once the turn ends, then goes out', function()
      local doc = {}
      local running = status_line.lines({ running = true, started = 0, owner = doc }, 5000)

      eq(' ' .. working(5000, 0, 'work', doc) .. ' · 5s · <C-c> interrupt', text(running[2]))

      local waning = status_line.lines({ running = false, owner = doc }, 5000)

      eq(' ', waning[2][1][1])
      eq(nil, text(waning[2]):find('interrupt', 1, true))
      assert.is_true(#waning[2] >= 2)

      mascot.stop()

      eq(nil, status_line.lines({ running = false, owner = doc }))
    end)

    it('never lights the line of a session that was not the one working', function()
      local doc = {}

      status_line.lines({ running = true, started = 0, owner = doc }, 0)

      eq(nil, status_line.lines({ running = false, owner = {} }))
    end)
  end)

  describe('sections', function()
    local function ids()
      return vim.tbl_map(function(section)
        return section.id
      end, status_line.sections())
    end

    after_each(function()
      status_line.unregister('background')
    end)

    it('runs in order: closing, ask, replay, sub-agents, held, working, queue', function()
      eq({ 'closing', 'ask', 'loading', 'subagents', 'held', 'working', 'queue' }, ids())
    end)

    it('takes a new line from one registered section, without touching the others', function()
      status_line.register({
        id = 'background',
        order = 60,
        exclusive = false,
        applies = function(state)
          return state.background == true
        end,
        lines = function()
          return { { { 'background task', 'UiMuted' } } }
        end,
      })

      local lines = status_line.lines({ running = true, background = true, started = 0 }, 3000)

      eq(
        { '', ' ' .. working(3000, 0) .. ' · 3s · <C-c> interrupt', 'background task' },
        { text(lines[1]), text(lines[2]), text(lines[3]) }
      )
      eq(nil, status_line.lines({ running = false, background = false }))
    end)

    it('lets an exclusive section keep the ones after it from drawing', function()
      local lines = status_line.lines({ running = true, started = 0, asks = { { text = 'Bash ls' } } }, 0)

      assert.is_nil(text(lines[2]):find('working', 1, true))
      assert.truthy(text(lines[2]):find('Allow Bash ls?', 1, true))
    end)

    it('replaces a section registered again under the same id', function()
      local before = #status_line.sections()

      status_line.register({
        id = 'ask',
        order = 20,
        exclusive = true,
        applies = function()
          return false
        end,
        lines = function()
          return {}
        end,
      })

      eq(before, #status_line.sections())
      eq(nil, status_line.lines({ running = false, asks = { { text = 'x' } } }))

      status_line.register(require('sn.transcript.status_line.ask'))
    end)
  end)

  describe('an answered card', function()
    local function card()
      return status_line.card_of(status_line.lines({
        running = true,
        asks = { { text = 'Bash ls', choices = { { key = '1', label = 'Allow' }, { key = '2', label = 'Deny' } } } },
      }, 0))
    end

    local function closing(tone)
      return { lines = card(), started = 1000, tone = tone or 'Accent' }
    end

    it('is the rows with the rail, without the spacer or the queue', function()
      eq(4, #card())
      eq('▎', card()[1][1][1])
    end)

    it('flashes its surface in the tone of the answer first, then collapses a row at a time', function()
      local flashing = status_line.closing_rows(closing('Error'), 1000)

      eq(4, #flashing)
      eq({ 'UiRailWarn', 'UiFlashError1' }, flashing[1][1][2])

      local early = #status_line.closing_rows(closing(), 1300)
      local late = #status_line.closing_rows(closing(), 1450)

      assert.is_true(early <= 4)
      assert.is_true(late < early)
      eq(0, #status_line.closing_rows(closing(), 1500))
    end)

    it('switches off like a tube: rows break into static, squash to a bright line, then a dot', function()
      local ms = status_line.closing_ms()
      local squashing = status_line.closing_rows(closing(), 1000 + ms * 0.6)
      local scrambled = text(squashing[1])

      assert.is_truthy(scrambled:find('[░▒▓▚▞]'))

      local bar = status_line.closing_rows(closing(), 1000 + ms * 0.8)

      eq(1, #bar)
      assert.is_truthy(text(bar[1]):find('━', 1, true))
      eq('UiFlashAccent1', bar[1][1][2])

      local dot = status_line.closing_rows(closing(), 1000 + ms * 0.95)

      eq('·', vim.trim(text(dot[1])))
    end)

    it('sits under the spacer while no ask is open, and goes once an ask returns', function()
      local lines = status_line.lines({ running = true, asks = {}, closing = closing() }, 1010)

      eq('', text(lines[1]))
      eq('▎', text(lines[2]):sub(1, 3))
      eq(nil, status_line.lines({ running = false, asks = {}, closing = closing() }, 5000))
    end)
  end)

  it('keeps every choice of a permission in view in a narrow window, one per line', function()
    local lines = status_line.lines({
      running = true,
      width = 40,
      asks = {
        {
          text = 'Bash: git -C /tmp/work status --short && npm test -- --coverage',
          choices = {
            { key = '1', label = 'Yes' },
            { key = '2', label = 'Yes, and don\'t ask again for git -C /tmp/work status --short commands' },
            { key = '3', label = 'No' },
          },
        },
      },
    })

    for i = 2, #lines do
      assert.is_true(vim.fn.strdisplaywidth(text(lines[i])) <= 40, text(lines[i]))
    end

    eq('▎  3 No', vim.trim(text(lines[5])))
    eq('▎  <C-c> interrupt', vim.trim(text(lines[6])))
  end)

  describe('a question from the agent', function()
    local translate = require('sn.servers.acp.translate')
    local fake_agent = require('sn.servers.acp.fake_agent')
    local ElicitationPrompt = require('sn.asks.Elicitation')

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
        '▎' .. theme.WAITING_ICON[1] .. 'Which database?  (+1 more)',
        '▎  Database',
        '▎  1 Postgres  relational',
        '▎  2 Redis',
        '▎  3 Other…',
        '▎  4 Skip',
        '▎  0 decline   <C-c> interrupt',
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

      eq('▎' .. theme.WAITING_ICON[1] .. 'Please answer the following questions.  1/2 ▰▰▰▱▱▱', shown[2])
      eq('▎  Tools: Which tools?', shown[3])
      eq({ '▎  1 ○ a', '▎  2 ◉ b', '▎  3 Done' }, { shown[4], shown[5], shown[6] })
    end)

    it('says where to write while an answer is being written, and shows what was wrong', function()
      local prompt = prompt_for({
        mode = 'form',
        message = 'Age?',
        requestedSchema = { properties = { age = { type = 'integer', title = 'Age' } } },
      })

      prompt:answer('1')

      local writing = texts(status_line.lines({ running = true, asks = { prompt } }))

      eq({ '▎  Age', '▎  write Age in the composer, or close it to go back' }, { writing[3], writing[4] })

      prompt:stop_writing()
      prompt.error = 'write a number'

      local shown = texts(status_line.lines({ running = true, asks = { prompt } }))

      eq('▎  write a number', shown[#shown - 1])
    end)

    it('asks even when no turn is running, as a sign-in link arrives on its own', function()
      local prompt = prompt_for({ mode = 'url', message = 'Sign in to linear', url = 'https://x', elicitationId = 'e' })

      eq({
        '',
        '▎' .. theme.WAITING_ICON[1] .. 'Sign in to linear',
        '▎  https://x',
        '▎  1 Open in the browser',
        '▎  0 decline   <C-c> interrupt',
        '  ' .. theme.QUEUE_ICON[1] .. 'queued later',
      }, texts(status_line.lines({ running = false, asks = { prompt }, queue = { 'later' } })))
    end)
  end)

  it('points at a request answered elsewhere', function()
    local lines = status_line.lines({ running = true, waiting = { { title = 'Write a.lua' } } })

    assert.truthy(text(lines[2]):find('waiting for you: Write a.lua', 1, true))
  end)

  it('says subagents are still working after the turn ended', function()
    local lines = status_line.lines({ running = false, active = { a = true, b = true }, queue = { 'next' } }, 0)

    eq(3, #lines)
    assert.truthy(text(lines[2]):find('2 subagents still working', 1, true))
    eq('  ' .. theme.QUEUE_ICON[1] .. 'queued next', text(lines[3]))
  end)
end)

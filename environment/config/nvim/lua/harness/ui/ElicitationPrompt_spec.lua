local console = require('core.console')
local elicitation = require('harness.types.elicitation')
local translate = require('harness.servers.acp.translate')
local fake_agent = require('harness.servers.acp.fake_agent')
local ElicitationPrompt = require('harness.ui.ElicitationPrompt')

local eq = assert.are.same

local function prompt_for(params)
  local request = assert(translate.elicitation_request(params))

  return ElicitationPrompt({ request = request, session = {} })
end

local function form(properties, required)
  return { mode = 'form', message = 'Fill in', requestedSchema = { properties = properties, required = required } }
end

local function labels(prompt)
  return vim.tbl_map(function(choice)
    return choice.key .. ' ' .. choice.label
  end, prompt:choices())
end

local function result(prompt)
  return prompt.future.done and prompt.future.result or nil
end

describe('harness.ui.ElicitationPrompt:', function()
  describe('a single choice with a free-text other', function()
    local prompt

    before_each(function()
      prompt = prompt_for(fake_agent.QUESTION)
    end)

    it('offers each option, then other and skip, by number', function()
      eq({ '1 Postgres', '2 Redis', '3 Other…', '4 Skip' }, labels(prompt))
      eq('relational', prompt:choices()[1].description)
    end)

    it('accepts the option picked by number', function()
      eq('set', prompt:answer('2'))
      eq(elicitation.accept({ question_0 = 'Redis' }), result(prompt))
    end)

    it('takes a written answer in place of an option', function()
      eq('write', prompt:answer('3'))
      eq('question_0_custom', prompt:writing().key)
      assert.is_nil(prompt:choice('1'))
      assert.is_true(prompt:submit_text('  MySQL  '))
      eq(elicitation.accept({ question_0_custom = 'MySQL' }), result(prompt))
    end)

    it('goes back to the options when writing is abandoned', function()
      prompt:answer('3')
      prompt:stop_writing()

      eq('Postgres', prompt:choice('1').label)
      assert.is_nil(prompt:writing())
    end)

    it('sends nothing for a skipped question', function()
      eq('skip', prompt:answer('4'))
      eq(elicitation.accept({}), result(prompt))
    end)

    it('declines on 0 and cancels when dismissed', function()
      eq('decline', prompt:answer('0'))
      eq(elicitation.decline(), result(prompt))

      local other = prompt_for(fake_agent.QUESTION)

      other:dismiss()
      eq(elicitation.cancel(), result(other))
      assert.is_false(other:is_open())
      assert.is_nil(other:choice('1'))
    end)

    it('ignores keys it does not offer', function()
      assert.is_false(prompt:answer('9'))
      assert.is_true(prompt:is_open())
    end)
  end)

  it('steps through several questions in order, showing where it is', function()
    local prompt = prompt_for(form({
      question_1 = { type = 'string', title = 'Cache', description = 'Which cache?', enum = { 'redis', 'none' } },
      question_0 = { type = 'string', title = 'Db', description = 'Which db?', enum = { 'pg' } },
    }))

    eq({ 1, 2, 'Db: Which db?' }, { prompt:view().step, prompt:view().count, prompt:view().label })
    prompt:answer('1')
    eq({ 2, 'Cache: Which cache?' }, { prompt:view().step, prompt:view().label })
    prompt:answer('2')

    eq(elicitation.accept({ question_0 = 'pg', question_1 = 'none' }), result(prompt))
  end)

  describe('a multi-select', function()
    local function multi(extra)
      return prompt_for(form({
        many = vim.tbl_extend('force', {
          type = 'array',
          items = {
            anyOf = { { const = 'a', title = 'A' }, { const = 'b', title = 'B' }, { const = 'c', title = 'C' } },
          },
        }, extra or {}),
        many_custom = { type = 'string', title = 'Other' },
      }))
    end

    it('toggles options by number, and sends them in the order offered when done', function()
      local prompt = multi()

      eq('toggle', prompt:answer('3'))
      prompt:answer('1')
      prompt:answer('2')
      prompt:answer('2')

      eq({ true, false, true }, {
        prompt:choices()[1].checked,
        prompt:choices()[2].checked,
        prompt:choices()[3].checked,
      })
      eq({ '1 A', '2 B', '3 C', '4 Other…', '5 Done' }, labels(prompt))

      eq('done', prompt:answer('5'))
      eq(elicitation.accept({ many = { 'a', 'c' } }), result(prompt))
    end)

    it('adds a written answer beside the picks, staying on the question', function()
      local prompt = multi()

      prompt:answer('1')
      prompt:answer('4')
      assert.is_true(prompt:submit_text('d'))
      assert.is_true(prompt:is_open())
      assert.is_true(prompt:choices()[4].checked)

      prompt:answer('5')
      eq(elicitation.accept({ many = { 'a' }, many_custom = 'd' }), result(prompt))
    end)

    it('holds to the fewest and most picks allowed', function()
      local prompt = multi({ minItems = 1, maxItems = 2 })

      prompt:answer('5')
      eq('pick at least 1', prompt:view().error)
      assert.is_true(prompt:is_open())

      prompt:answer('1')
      prompt:answer('2')
      prompt:answer('3')
      eq('pick at most 2', prompt:view().error)
      assert.is_nil(prompt:choices()[3].checked or nil)

      prompt:answer('5')
      eq(elicitation.accept({ many = { 'a', 'b' } }), result(prompt))
    end)

    it('starts from the picks the agent suggests', function()
      local prompt = multi({ default = { 'b' } })

      prompt:answer('5')
      eq(elicitation.accept({ many = { 'b' } }), result(prompt))
    end)
  end)

  it('asks yes or no for a boolean, with its default', function()
    local prompt = prompt_for(form({ ok = { type = 'boolean', title = 'Proceed?', default = false } }))

    eq({ '1 Yes', '2 No', '3 Use the default (no)', '4 Skip' }, labels(prompt))
    prompt:answer('2')
    eq(elicitation.accept({ ok = false }), result(prompt))

    local defaulted = prompt_for(form({ ok = { type = 'boolean', default = false } }))

    eq('default', defaulted:answer('3'))
    eq(elicitation.accept({ ok = false }), result(defaulted))
  end)

  describe('a written answer', function()
    it('offers writing first, and no skip when it is required', function()
      local prompt = prompt_for(form({ name = { type = 'string', title = 'Name' } }, { 'name' }))

      eq({ '1 Write an answer…' }, labels(prompt))
      prompt:answer('1')
      eq('Name', prompt:view().writing)
      eq({}, prompt:view().choices)
      assert.is_true(prompt:submit_text('Ada'))
      eq(elicitation.accept({ name = 'Ada' }), result(prompt))
    end)

    it('checks the length of text, counting characters', function()
      local prompt = prompt_for(form({ code = { type = 'string', minLength = 2, maxLength = 3 } }))

      prompt:answer('1')
      eq({ nil, 'write at least 2 characters' }, { prompt:submit_text('x') })
      eq({ nil, 'write at most 3 characters' }, { prompt:submit_text('abcd') })
      assert.is_true(prompt:submit_text('éé'))
    end)

    it('reads numbers and whole numbers within their bounds', function()
      local prompt = prompt_for(form({
        age = { type = 'integer', minimum = 0, maximum = 150 },
        ratio = { type = 'number' },
      }))

      prompt:answer('1')
      eq({ nil, 'write a number' }, { prompt:submit_text('old') })
      eq({ nil, 'write a whole number' }, { prompt:submit_text('1.5') })
      eq({ nil, 'write at most 150' }, { prompt:submit_text('200') })
      assert.is_true(prompt:submit_text('42'))

      prompt:answer('1')
      assert.is_true(prompt:submit_text('0.5'))

      eq(elicitation.accept({ age = 42, ratio = 0.5 }), result(prompt))
    end)

    it('refuses text when nothing is being written', function()
      local prompt = prompt_for(form({ name = { type = 'string' } }))

      eq({ nil, 'nothing is waiting for an answer' }, { prompt:submit_text('x') })
    end)
  end)

  it('puts options past nine keys behind a list to pick from', function()
    local options = {}

    for i = 1, 12 do
      options[i] = 'o' .. i
    end

    local prompt = prompt_for(form({ pick = { type = 'string', enum = options } }))
    local shown = labels(prompt)

    eq(9, #shown)
    eq({ '7 o7', '8 More (5)…', '9 Skip' }, { shown[7], shown[8], shown[9] })
    eq(12, #prompt:options())
    eq('pick', prompt:answer('8'))
    assert.is_true(prompt:pick('o11'))
    eq(elicitation.accept({ pick = 'o11' }), result(prompt))
  end)

  it('opens a url in the browser and accepts', function()
    local opened
    local original = console.open_url

    console.open_url = function(url)
      opened = url
    end

    local prompt = prompt_for({ mode = 'url', message = 'Sign in', url = 'https://x', elicitationId = 'e1' })

    eq({ '1 Open in the browser' }, labels(prompt))
    eq({ 'https://x', 'Sign in' }, { prompt:view().url, prompt:view().message })

    local ok, err = pcall(prompt.answer, prompt, '1')

    console.open_url = original

    assert(ok, err)
    eq('https://x', opened)
    eq(elicitation.accept(), result(prompt))
  end)
end)

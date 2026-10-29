local content = require('harness.types.content')
local translate = require('harness.servers.acp.translate')

local eq = assert.are.same

describe('harness.servers.acp.translate:', function()
  local selection = content.Attachment({
    label = 'a.lua:2-3',
    source = 'a.lua',
    path = '/w/a.lua',
    range = { 2, 3 },
    lines = { 'two', 'three' },
    language = 'lua',
  })

  it('sends a selection as an embedded resource when the agent takes them, else inline', function()
    local embedded = translate.attachment(selection, { embeddedContext = true })
    local inline = translate.attachment(selection, {})

    eq('resource', embedded.type)
    eq({ uri = 'file:///w/a.lua#L2-3', text = 'two\nthree', mimeType = 'text/plain' }, embedded.resource)
    eq('text', inline.type)
    eq('Selected lines 2-3 of a.lua:\n```lua\ntwo\nthree\n```', inline.text)
  end)

  it('sends anything else inline under its title', function()
    local block = content.Attachment({ title = 'The code block', lines = { 'x' }, language = 'lua' })

    eq('The code block:\n```lua\nx\n```', translate.attachment(block, { embeddedContext = true }).text)
  end)

  it('lays a prompt out as instructions, where the user is, attachments, then the text', function()
    local prompt = content.prompt(
      'explain',
      content.context({ where = '<editor-context>here</editor-context>', attachments = { selection } }),
      '<harness-instructions>be brief</harness-instructions>'
    )

    eq(
      {
        '<harness-instructions>be brief</harness-instructions>',
        '<editor-context>here</editor-context>',
        'resource',
        'explain',
      },
      vim.tbl_map(function(block)
        return block.text or block.type
      end, translate.prompt(prompt, { embeddedContext = true }))
    )
    eq({ { type = 'text', text = 'plain' } }, translate.prompt(content.prompt('plain')))
  end)

  describe('elicitation_request', function()
    local function form(properties, required)
      return {
        mode = 'form',
        message = 'Fill in',
        requestedSchema = { type = 'object', properties = properties, required = required },
      }
    end

    local function kinds(request)
      return vim.tbl_map(function(field)
        return field.key .. ':' .. field.kind
      end, request.fields)
    end

    it('reads every field kind ACP defines, in natural key order', function()
      local request = translate.elicitation_request(form({
        name = { type = 'string', title = 'Name', minLength = 1, maxLength = 20, default = 'x' },
        age = { type = 'integer', minimum = 0, maximum = 150 },
        ratio = { type = 'number' },
        ok = { type = 'boolean', default = true },
        pick = { type = 'string', enum = { 'a', 'b' }, enumNames = { 'Alpha' } },
        many = { type = 'array', items = { anyOf = { { const = 'x', title = 'X' } } }, minItems = 1 },
      }, { 'name' }))

      eq({ 'age:integer', 'many:multi', 'name:text', 'ok:boolean', 'pick:choice', 'ratio:number' }, kinds(request))

      local by_key = {}

      for _, field in ipairs(request.fields) do
        by_key[field.key] = field
      end

      eq({ true, 1, 20, 'x' }, { by_key.name.required, by_key.name.min, by_key.name.max, by_key.name.default })
      eq({ 0, 150 }, { by_key.age.min, by_key.age.max })
      eq(true, by_key.ok.default)
      eq({ 'Alpha', 'b' }, { by_key.pick.options[1].label, by_key.pick.options[2].label })
      eq({ 'x', 'X', 1 }, { by_key.many.options[1].value, by_key.many.options[1].label, by_key.many.min })
    end)

    it('drops an option description that only repeats its label', function()
      local request = translate.elicitation_request(form({
        pick = {
          type = 'string',
          oneOf = {
            { const = 'vim', title = 'Neovim', description = 'Neovim' },
            { const = 'zig', description = 'fast' },
          },
        },
      }))

      eq({ nil, 'fast' }, { request.fields[1].options[1].description, request.fields[1].options[2].description })
      eq('zig', request.fields[1].options[2].label)
    end)

    it('orders numbered keys by number, so question_10 follows question_2', function()
      local properties = {}

      for _, n in ipairs({ 10, 2, 1 }) do
        properties['question_' .. n] = { type = 'string', enum = { 'a' } }
      end

      eq(
        { 'question_1:choice', 'question_2:choice', 'question_10:choice' },
        kinds(translate.elicitation_request(form(properties)))
      )
    end)

    it('pairs a free-text <key>_custom field with the choice it belongs to', function()
      local request = translate.elicitation_request(require('harness.servers.acp.fake_agent').QUESTION)

      eq({ 'question_0:choice', 'question_0_custom:text' }, kinds(request))
      eq('question_0_custom', request.fields[1].other)
      eq({ 'Postgres', 'relational' }, { request.fields[1].options[1].value, request.fields[1].options[1].description })
    end)

    it('drops an optional field it cannot show, and refuses a form that requires one', function()
      local properties = { weird = { type = 'object' }, name = { type = 'string' } }

      eq({ 'name:text' }, kinds(translate.elicitation_request(form(properties))))

      local request, why = translate.elicitation_request(form(properties, { 'weird' }))

      eq(nil, request)
      assert.truthy(why:find('weird', 1, true))
    end)

    it('reads a url request, and refuses one without a url or in an unknown mode', function()
      local request = translate.elicitation_request({
        mode = 'url',
        message = 'Sign in',
        url = 'https://x',
        elicitationId = 'e1',
        toolCallId = 't1',
      })

      eq({ 'url', 'https://x', 'e1', 't1' }, { request.mode, request.url, request.id, request.tool })
      eq(nil, (translate.elicitation_request({ mode = 'url', message = 'x' })))
      eq(nil, (translate.elicitation_request({ mode = '_custom', message = 'x' })))
    end)

    it('treats JSON nulls as absent', function()
      local request = translate.elicitation_request({
        mode = 'form',
        message = 'x',
        toolCallId = vim.NIL,
        requestedSchema = { properties = { a = { type = 'string', title = vim.NIL, default = vim.NIL } } },
      })

      eq({ nil, nil, nil }, { request.tool, request.fields[1].title, request.fields[1].default })
    end)
  end)

  describe('elicitation_response', function()
    local elicitation = require('harness.types.elicitation')

    it('sends the content of an accept as a JSON object, leaving out empty picks', function()
      local reply = translate.elicitation_response(elicitation.accept({ a = 'x', many = {}, n = 3, ok = false }))

      eq({ action = 'accept', content = { a = 'x', n = 3, ok = false } }, reply)
      eq('{}', vim.json.encode(translate.elicitation_response(elicitation.accept({})).content))
    end)

    it('sends decline and cancel without content', function()
      eq({ action = 'decline' }, translate.elicitation_response(elicitation.decline()))
      eq({ action = 'cancel' }, translate.elicitation_response(elicitation.cancel()))
    end)
  end)
end)

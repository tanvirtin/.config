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
end)

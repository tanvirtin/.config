local content = require('harness.types.content')

local eq = assert.are.same

describe('harness.types.content:', function()
  it('builds a prompt from text and the editor context, and names its labelled attachments', function()
    local context = content.attach(content.context({ where = 'here' }), { label = 'a.lua:1', lines = { 'x' } })

    content.attach(context, { title = 'The code block', lines = { 'y' } })

    local prompt = content.prompt('go', context, 'rules')

    eq({ 'go', 'here', 'rules', 2 }, { prompt.text, prompt.where, prompt.instructions, #prompt.attachments })
    eq({ 'a.lua:1' }, content.labels(context))
    eq(nil, content.labels(content.context()))
    eq('go', content.prompt('go').text)
  end)
end)

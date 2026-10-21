local context = require('harness.context')

local eq = assert.are.same

describe('harness.context:', function()
  before_each(function()
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
    vim.api.nvim_win_set_cursor(0, { 2, 1 })
  end)

  it('says where the user is, in an editor-context tag', function()
    local text = context.capture(vim.api.nvim_get_current_win()).text

    assert.is_truthy(text:find('^<editor%-context>'))
    assert.is_truthy(text:find('%[No Name%] %(bufnr ' .. vim.api.nvim_get_current_buf() .. '%), line 2, col 2'))
    assert.is_truthy(text:find('</editor%-context>$'))
  end)

  it('mentions a selected range', function()
    assert.is_truthy(context.capture(vim.api.nvim_get_current_win(), { 2, 3 }).text:find('selected lines 2-3', 1, true))
  end)

  it('sends the selected lines as an embedded resource when the agent takes them, else inline', function()
    vim.api.nvim_buf_set_name(0, vim.fn.tempname() .. '.lua')
    vim.bo.filetype = 'lua'

    local captured = context.capture(vim.api.nvim_get_current_win(), { 2, 3 })
    local embedded = context.blocks(captured, { embeddedContext = true })
    local inline = context.blocks(captured, {})

    eq('resource', embedded[2].type)
    eq('two\nthree', embedded[2].resource.text)
    assert.is_truthy(embedded[2].resource.uri:find('^file://.*%.lua#L2%-3$'))
    eq('text', inline[2].type)
    assert.is_truthy(inline[2].text:find('Selected lines 2-3 of', 1, true))
    assert.is_truthy(inline[2].text:find('```lua\ntwo\nthree\n```', 1, true))
    eq(1, #context.blocks(context.capture(vim.api.nvim_get_current_win()), { embeddedContext = true }))
    eq({ { type = 'text', text = 'plain' } }, context.blocks('plain'))
  end)

  it('strips the tag from a replayed prompt', function()
    local text = context.capture(vim.api.nvim_get_current_win()).text .. '\n\nrename x'

    eq('rename x', context.strip(text))
    eq('plain', context.strip('plain'))
  end)
end)

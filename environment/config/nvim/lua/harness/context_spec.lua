local context = require('harness.context')

local eq = assert.are.same

describe('harness.context:', function()
  before_each(function()
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
    vim.api.nvim_win_set_cursor(0, { 2, 1 })
  end)

  it('says where the user is, in an editor-context tag', function()
    local text = context.capture(vim.api.nvim_get_current_win())

    assert.is_truthy(text:find('^<editor%-context>'))
    assert.is_truthy(text:find('%[No Name%] %(bufnr ' .. vim.api.nvim_get_current_buf() .. '%), line 2, col 2'))
    assert.is_truthy(text:find('</editor%-context>$'))
  end)

  it('mentions a selected range', function()
    assert.is_truthy(context.capture(vim.api.nvim_get_current_win(), { 2, 3 }):find('selected lines 2-3', 1, true))
  end)

  it('strips the tag from a replayed prompt', function()
    local text = context.capture(vim.api.nvim_get_current_win()) .. '\n\nrename x'

    eq('rename x', context.strip(text))
    eq('plain', context.strip('plain'))
  end)
end)

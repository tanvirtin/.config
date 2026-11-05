local editor = require('core.editor')
local Window = require('core.Window')

local eq = assert.are.same

describe('core.editor:', function()
  it('reports the mode and the tab it is in', function()
    eq('n', editor.mode())
    eq(vim.fn.tabpagenr(), editor.tab_number())
    eq(vim.fn.tabpagenr('$'), editor.tab_count())
  end)

  it('lists every tab with its windows', function()
    local tabs = editor.tabs()

    eq(editor.tab_count(), #tabs)
    eq(
      Window.get_current().win_id,
      vim.tbl_filter(function(tab)
        return tab.number == editor.tab_number()
      end, tabs)[1].windows[1].win_id
    )
  end)

  it('tells a command that exists from one that does not', function()
    eq(true, editor.command_exists('edit'))
    eq(false, editor.command_exists('NoSuchCommandAnywhere'))
  end)

  it('runs a command and reports failure instead of raising', function()
    eq(true, (editor.run('echo', { '"x"' })))

    local ok = editor.run('NoSuchCommandAnywhere')

    eq(false, ok)
  end)

  it('returns the output of an Ex command', function()
    eq('hi', editor.exec('echo "hi"'))
  end)

  it('presses keys as typed, reading key names', function()
    local buffer = vim.api.nvim_create_buf(false, true)
    local previous = vim.api.nvim_get_current_buf()

    vim.api.nvim_set_current_buf(buffer)
    editor.press('ihello<Esc>')
    eq({ 'hello' }, vim.api.nvim_buf_get_lines(buffer, 0, -1, false))

    vim.api.nvim_set_current_buf(previous)
    vim.api.nvim_buf_delete(buffer, { force = true })
  end)
end)

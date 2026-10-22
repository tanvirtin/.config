local quickfix = require('core.quickfix')

local eq = assert.are.same

describe('core.quickfix:', function()
  after_each(function()
    vim.cmd('silent! cclose')
    vim.fn.setqflist({}, 'r')
  end)

  it('fills the quickfix list with titled locations and reads them back', function()
    local path = vim.fn.tempname()

    vim.fn.writefile({ 'a', 'b', 'c' }, path)

    eq(
      2,
      quickfix.set(
        { { path = path, line = 2, text = 'second' }, { path = path, line = 3, col = 2 } },
        { title = 'edits' }
      )
    )

    local list = quickfix.get()

    path = vim.fn.resolve(path)
    list.items[1].path = vim.fn.resolve(list.items[1].path)
    list.items[2].path = vim.fn.resolve(list.items[2].path)

    eq('edits', list.title)
    eq({ path = path, line = 2, col = 1, text = 'second' }, list.items[1])
    eq({ path = path, line = 3, col = 2, text = '' }, list.items[2])
    os.remove(path)
  end)

  it('opens the quickfix window when asked', function()
    quickfix.set({}, { title = 'empty', open = true })

    local found = false

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == 'quickfix' then found = true end
    end

    eq(true, found)
  end)
end)

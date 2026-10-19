local links = require('harness.ui.links')

local eq = assert.are.same

describe('harness.ui.links:', function()
  local dir

  before_each(function()
    links.clear_cache()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/lua', 'p')
    vim.fn.writefile({ 'one', 'two', 'three' }, dir .. '/lua/a.lua')
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  it('resolves nvim:// file links, with a line, relative to the session directory', function()
    eq({ path = dir .. '/lua/a.lua', line = 2 }, links.resolve('link', 'nvim://file/lua/a.lua#L2', dir))
    eq(true, links.resolve('link', 'nvim://file/lua/gone.lua', dir).missing)
  end)

  it('resolves buffer links, urls and plain paths', function()
    local buf = vim.api.nvim_create_buf(false, true)

    eq({ bufnr = buf }, links.resolve('link', 'nvim://buf/' .. buf, dir))
    eq({ url = 'https://x.dev' }, links.resolve('link', 'https://x.dev', dir))
    eq({ path = dir .. '/lua/a.lua', line = 3 }, links.resolve('link', 'lua/a.lua:3', dir))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('treats code spans as links only when they name a file that exists', function()
    eq({ path = dir .. '/lua/a.lua', line = 3 }, links.resolve('code', 'lua/a.lua:3', dir))
    assert.is_nil(links.resolve('code', 'lua/missing.lua', dir))
    assert.is_nil(links.resolve('code', 'local x = 1', dir))
    assert.is_nil(links.resolve('code', 'x', dir))
  end)

  it('opens a file in a new tab at its line', function()
    local tabs = #vim.api.nvim_list_tabpages()

    eq(true, links.open({ path = dir .. '/lua/a.lua', line = 2 }))
    eq(tabs + 1, #vim.api.nvim_list_tabpages())
    eq(vim.uv.fs_realpath(dir .. '/lua/a.lua'), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
    eq(2, vim.api.nvim_win_get_cursor(0)[1])
    eq(false, links.open({ path = 'x', missing = true }))
    vim.cmd('tabclose')
  end)
end)

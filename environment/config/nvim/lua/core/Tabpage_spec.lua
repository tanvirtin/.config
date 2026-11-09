local Buffer = require('core.Buffer')
local Tabpage = require('core.Tabpage')

local eq = assert.are.same

describe('core.Tabpage:', function()
  after_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
  end)

  it('opens a named tab of its own and moves to it, leaving the old one as it was', function()
    local origin = Tabpage.current()
    local tab = Tabpage.open({ name = 'Review: login' })

    eq(2, Tabpage.count())
    assert.is_true(tab:is_current())
    assert.is_false(origin:is_current())
    eq('Review: login', tab:get_name())
    eq(1, #tab:windows())

    origin:focus()
    assert.is_true(origin:is_current())
    tab:focus()
    assert.is_true(tab:contains(tab:window()))
  end)

  it('closes itself, deleting the buffers it owns, and says so to whoever asked', function()
    local tab = Tabpage.open()
    local owned = tab:own(Buffer():create(false, true))
    local closed = 0

    tab:window():set_buffer(owned)
    tab:on_close(function()
      closed = closed + 1
    end)

    assert.is_true(tab:close())
    eq(false, tab:is_valid())
    eq(false, Buffer.exists(owned.bufnr))
    eq(1, closed)
  end)

  it('tells its listeners when the user closes it', function()
    local tab = Tabpage.open()
    local closed = false

    tab:on_close(function()
      closed = true
    end)
    vim.cmd('tabclose')

    eq(true, closed)
    eq(1, Tabpage.count())
  end)

  it('keeps the last tab open, since Neovim cannot close it, but still lets go of its buffers', function()
    local tab = Tabpage.current()
    local owned = tab:own(Buffer():create(false, true))

    eq(false, tab:close())
    eq(true, tab:is_valid())
    eq(false, Buffer.exists(owned.bufnr))
  end)

  it('wipes the blank buffer it opened with once something replaces it', function()
    local tab = Tabpage.open()
    local blank = tab:window():get_buffer().bufnr

    tab:window():set_buffer(Buffer():create(false, true))

    eq(false, Buffer.exists(blank))
  end)
end)

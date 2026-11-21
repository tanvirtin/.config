local Window = require('core.editor.Window')
local panes = require('core.editor.panes')

local eq = assert.are.same

describe('panes:', function()
  local dir, a, b, columns, lines

  local function write(name)
    local path = dir .. '/' .. name
    vim.fn.writefile({ 'one', 'two', 'three', 'four' }, path)
    return path
  end

  local function tiled()
    local count = 0
    for _, window in ipairs(Window.list_tab()) do
      if not window:is_floating() then count = count + 1 end
    end
    return count
  end

  before_each(function()
    columns, lines = vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 200, 50
    vim.cmd('tabnew')
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    a, b = write('a.lua'), write('b.lua')
  end)

  after_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.o.columns, vim.o.lines = columns, lines
    vim.fn.delete(dir, 'rf')
  end)

  it('should open a pane beside the anchor without moving focus', function()
    local anchor = Window.get_current()

    local window = panes.show('s1', anchor, 'code', a, { line = 3 })

    eq(2, tiled())
    eq(true, anchor:is_focused())
    eq(3, window:get_cursor()[1])
    eq({ owner = 's1', name = 'code' }, window:get_var(panes.VAR))
  end)

  it('should put the pane left of a wide anchor and above a narrow one', function()
    local anchor = Window.get_current()
    local window = panes.show('s1', anchor, 'code', a)

    assert.is_true(window:get_position()[2] < anchor:get_position()[2])

    panes.close('s1')
    vim.o.columns = 100

    window = panes.show('s1', anchor, 'code', a)

    assert.is_true(window:get_position()[1] < anchor:get_position()[1])
  end)

  it('should reuse a pane by name', function()
    local anchor = Window.get_current()
    local first = panes.show('s1', anchor, 'code', a)
    local second = panes.show('s1', anchor, 'code', b, { line = 2 })

    eq(first.win_id, second.win_id)
    eq(2, tiled())
    eq(vim.fn.resolve(b), vim.fn.resolve(vim.api.nvim_buf_get_name(second:get_buffer().bufnr)))
  end)

  it('should split the largest other window rather than the anchor', function()
    local anchor = Window.get_current()

    panes.show('s1', anchor, 'code', a)
    panes.show('s1', anchor, 'peek', b)

    eq(3, tiled())
    eq(2, #panes.list('s1'))
  end)

  it('should keep owners apart', function()
    local anchor = Window.get_current()
    local mine = panes.show('s1', anchor, 'code', a)
    local theirs = panes.show('s2', anchor, 'code', b)

    assert.are_not.equal(mine.win_id, theirs.win_id)
    eq(1, panes.close('s2'))
    eq(true, mine:is_valid())
  end)

  it('should close only its own panes, never the user\'s windows', function()
    local anchor = Window.get_current()

    vim.cmd('vsplit')
    local user = Window.get_current()
    anchor:focus()

    panes.show('s1', anchor, 'code', a)
    panes.show('s1', anchor, 'peek', b)

    eq(1, panes.close('s1', 'peek'))
    eq(1, panes.close('s1'))
    eq(true, user:is_valid())
    eq(true, anchor:is_valid())
    eq(0, #panes.list('s1'))
  end)
end)

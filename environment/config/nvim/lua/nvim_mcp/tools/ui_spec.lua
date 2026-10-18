local compact = require('compact')
local surfaces = require('surfaces')
local tools = require('nvim_mcp.tools')

local eq = assert.are.same

local function run(name, args, caller)
  return tools.run(name, args or {}, caller)
end

local function fixture()
  local root = vim.fs.normalize(vim.fn.tempname())

  vim.fn.mkdir(root .. '/lua', 'p')
  vim.fn.writefile({ 'local a = 1', 'local greet = 2', 'return a' }, root .. '/lua/a.lua')
  vim.fn.writefile({ 'greet()' }, root .. '/b.lua')

  return vim.uv.fs_realpath(root)
end

describe('nvim_mcp.tools.ui:', function()
  local root

  before_each(function()
    surfaces.close_all()
    compact.reset_stats()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    tools.set_focus(nil)
    root = fixture()
  end)

  after_each(function()
    surfaces.close_all()
  end)

  describe('search', function()
    it('returns compact grep results grouped by file, and counts what it saved', function()
      local out = run('search', { source = 'grep', query = 'greet', path = root }, 'h1')

      assert.is_truthy(out:find('b.lua (1)\n  1: greet()', 1, true))
      assert.is_truthy(out:find('lua/a.lua (1)\n  2:7: local greet = 2', 1, true))
      eq(1, compact.stats('h1').calls)
      assert.is_true(compact.stats('h1').saved_tokens > 0)
    end)

    it('lists files as paths', function()
      local out = run('search', { source = 'files', query = 'a.lua', path = root })

      eq('1 results\nlua/a.lua', out)
    end)

    it('also shows the search in a picker when asked', function()
      local out = run('search', { source = 'grep', query = 'greet', path = root, show = true }, 'h1')
      local picker = surfaces.all()[1]

      assert.is_truthy(out:find('shown to the user in ' .. picker.id, 1, true))
      eq('h1', picker.owner)

      vim.wait(1000, function()
        return #picker._items == 2
      end)
      assert.is_truthy(run('ui_read', { surface = picker.id }):find('query "greet", 2 of 2', 1, true))
    end)
  end)

  describe('surfaces', function()
    it('shows a list and drives it', function()
      local out = run('ui_show', {
        kind = 'list',
        title = 'Greets',
        items = { { path = root .. '/b.lua', line = 1, text = 'greet()' } },
      }, 'h1')
      local list = surfaces.all()[1]

      assert.is_truthy(
        out:find(list.id .. ' list "Greets" [ready] by h1 commands: add(items) close() cursor(index)', 1, true)
      )

      local after = run('ui_command', {
        surface = list.id,
        command = 'add',
        args = { items = { { path = root .. '/lua/a.lua', line = 2, text = 'local greet = 2' } } },
      })

      assert.is_truthy(after:find('Greets', 1, true))
      assert.is_truthy(after:find('lua/a.lua (1)', 1, true))
      assert.is_truthy(run('ui_surfaces'):find(list.id .. ' list', 1, true))
    end)

    it('shows a panel', function()
      run('ui_show', { kind = 'panel', title = 'Notes', markdown = '- one' })

      eq({ '# Notes', '', '- one' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it('lets the user pick, and reads their choice back', function()
      local out = run('ui_pick', { title = 'Which', items = { 'red', 'blue' } })
      local picker = surfaces.all()[1]

      assert.is_truthy(out:find('the user is choosing', 1, true))

      run('ui_command', { surface = picker.id, command = 'move' })
      run('ui_command', { surface = picker.id, command = 'select' })
      vim.wait(200, function()
        return picker.state == 'chosen'
      end)

      assert.is_truthy(run('ui_read', { surface = picker.id }):find('chosen: blue', 1, true))
    end)

    it('reports an unknown surface and an unknown command', function()
      local ok, err = pcall(run, 'ui_read', { surface = 'u999' })
      eq(false, ok)
      eq('no surface u999 (ui_surfaces lists them)', err)

      run('ui_show', { kind = 'panel', title = 'P', markdown = '' })

      ok, err = pcall(run, 'ui_command', { surface = surfaces.all()[1].id, command = 'fly' })
      eq(false, ok)
      assert.is_truthy(err:find('panel has no command fly', 1, true))
      eq(
        'no surfaces open',
        (function()
          surfaces.close_all()
          return run('ui_surfaces')
        end)()
      )
    end)
  end)

  describe('screen', function()
    it('shows every window with its visible lines and the cursor', function()
      vim.cmd('edit ' .. root .. '/lua/a.lua')
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local out = run('ui_screen')

      assert.is_truthy(out:find('(current): ', 1, true))
      assert.is_truthy(out:find('lua/a.lua [lua] lines 1-3 of 3, cursor 2:1', 1, true), out)
      assert.is_truthy(out:find('>   2 local greet = 2', 1, true))
    end)

    it('types keys and shows the result', function()
      vim.cmd('edit ' .. root .. '/lua/a.lua')

      local out = run('ui_keys', { keys = 'G' })

      eq(3, vim.api.nvim_win_get_cursor(0)[1])
      assert.is_truthy(out:find('cursor 3:1', 1, true))
    end)
  end)
end)

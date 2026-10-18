local surfaces = require('surfaces')

local eq = assert.are.same

local function settle(predicate)
  vim.wait(1000, predicate or function()
    return false
  end, 10)
end

local function fixture()
  local root = vim.fs.normalize(vim.fn.tempname())

  vim.fn.mkdir(root .. '/lua', 'p')
  vim.fn.writefile({ 'local a = 1', 'local greet = 2', 'return a' }, root .. '/lua/a.lua')
  vim.fn.writefile({ 'greet()' }, root .. '/b.lua')

  return vim.uv.fs_realpath(root)
end

describe('surfaces:', function()
  before_each(function()
    surfaces.close_all()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
  end)

  after_each(function()
    surfaces.close_all()
  end)

  describe('picker', function()
    local function letters()
      local chosen
      local picker = surfaces.pick({
        title = 'Letters',
        items = { { label = 'alpha' }, { label = 'beta' }, { label = 'gamma' } },
        on_select = function(item)
          chosen = item
        end,
      })

      return picker, function()
        return chosen
      end
    end

    it('is driven by commands the way a person drives it with keys', function()
      local picker, chosen = letters()

      eq('ready', picker.state)

      picker:command('query', { text = 'a' })
      assert.is_truthy(picker:snapshot():find('query "a", 3 of 3 items', 1, true))

      picker:command('query', { text = 'gam' })
      assert.is_truthy(picker:snapshot():find('selected: gamma', 1, true))

      picker:command('select')
      settle(function()
        return chosen() ~= nil
      end)

      eq('gamma', chosen().label)
      eq('chosen', picker.state)
      eq(nil, surfaces.get(picker.id))
    end)

    it('moves the selection', function()
      local picker = letters()

      picker:command('move', { count = 2 })
      assert.is_truthy(picker:snapshot():find('selected: gamma', 1, true))

      picker:command('move', { direction = 'up' })
      assert.is_truthy(picker:snapshot():find('selected: beta', 1, true))
    end)

    it('rejects unknown commands and bad arguments', function()
      local picker = letters()

      local ok, err = pcall(picker.command, picker, 'fly')
      eq(false, ok)
      assert.is_truthy(err:find('picker has no command fly (commands: close, move, query, select)', 1, true))

      ok, err = pcall(picker.command, picker, 'move', { direction = 'sideways' })
      eq(false, ok)
      assert.is_truthy(err:find('invalid arguments for move', 1, true))
    end)

    it('lists itself with its state and commands', function()
      local picker = letters()

      eq({ picker }, surfaces.all())
      eq(
        picker.id .. ' picker "Letters" [ready] commands: close() move(direction?, count?) query(text) select(how?)',
        picker:describe()
      )
    end)

    it('loads a source, then opens the choice', function()
      local root = fixture()
      local picker = surfaces.pick({ title = 'Files', source = 'files', source_opts = { cwd = root } })

      settle(function()
        return picker.state == 'ready' and #picker._items == 2
      end)

      picker:command('query', { text = 'a.lua' })
      picker:command('select')
      settle(function()
        return vim.api.nvim_buf_get_name(0):find('a.lua', 1, true) ~= nil
      end)

      eq(root .. '/lua/a.lua', vim.api.nvim_buf_get_name(0))
    end)

    it('searches a live source as the query changes', function()
      local root = fixture()
      local picker = surfaces.pick({ title = 'Grep', source = 'grep', source_opts = { cwd = root } })

      picker:command('query', { text = 'greet' })
      settle(function()
        return #picker._items == 2 and picker.state == 'ready'
      end)

      eq(2, #picker._items)
      assert.is_truthy(picker:snapshot():find('2 of 2 items', 1, true))
    end)
  end)

  describe('footer', function()
    local function footer_text()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local footer = vim.api.nvim_win_get_config(win).footer

        if footer and #footer > 0 then
          return table.concat(vim.tbl_map(function(chunk)
            return type(chunk) == 'table' and chunk[1] or chunk
          end, footer))
        end
      end
    end

    it('names the keys along the bottom border, actions included', function()
      local picker = surfaces.pick({
        title = 'Things',
        items = { { label = 'a' } },
        actions = { { key = '<C-x>', desc = 'delete', run = function() end } },
      })

      local text = footer_text()

      assert.is_truthy(text:find('<CR> open', 1, true))
      assert.is_truthy(text:find('<C-x> delete', 1, true))
      assert.is_truthy(text:find('<Esc> close', 1, true))
      picker:command('close')
    end)

    it('shows the hints a picker is given instead', function()
      local picker = surfaces.pick({ title = 'T', items = {}, hints = { { '<CR>', 'go' } } })

      eq(' <CR> go ', footer_text())
      picker:command('close')
    end)
  end)

  describe('text from agents', function()
    it('shows labels, queries and panel text that contain newlines', function()
      local picker = surfaces.pick({ title = 'Pick', items = { { label = 'one\ntwo', description = 'a\nb' } } })

      picker:command('query', { text = 'one\ntwo' })
      assert.is_truthy(picker:snapshot():find('selected: one two', 1, true))
      picker:command('close')

      local panel = surfaces.panel({ title = 'P', lines = { 'a\nb' } })

      eq({ '# P', '', 'a', 'b' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      panel:command('close')
    end)
  end)

  describe('select', function()
    it('answers vim.ui.select with the choice', function()
      local answer

      require('surfaces.select').ui_select({ 'one', 'two' }, { prompt = 'Pick:' }, function(item, index)
        answer = { item, index }
      end)

      local picker = surfaces.all()[1]

      eq('Pick', picker.title)

      picker:command('move')
      picker:command('select')
      settle(function()
        return answer ~= nil
      end)

      eq({ 'two', 2 }, answer)
    end)

    it('answers nil when dismissed', function()
      local answered, answer = false, 'unset'

      require('surfaces.select').ui_select({ 'one' }, {}, function(item)
        answered, answer = true, item
      end)

      surfaces.all()[1]:command('close')
      settle(function()
        return answered
      end)

      eq(nil, answer)
    end)
  end)

  describe('list', function()
    local function items(root)
      return {
        { path = root .. '/b.lua', line = 1, text = 'greet()' },
        { path = root .. '/lua/a.lua', line = 2, text = 'local greet = 2' },
      }
    end

    it('shows locations grouped by file in a split, and opens them', function()
      local root = fixture()
      local source = vim.api.nvim_get_current_win()
      local list = surfaces.list({ title = 'Greets', items = items(root) })
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

      eq('Greets (2)', lines[1])
      eq({ 'b.lua', '     1  greet()' }, { vim.fn.fnamemodify(lines[2], ':t'), lines[3] })

      list:command('open', { index = 2 })

      eq(source, vim.api.nvim_get_current_win())
      eq(root .. '/lua/a.lua', vim.api.nvim_buf_get_name(0))
      eq(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('points at an item and grows as results arrive', function()
      local root = fixture()
      local list = surfaces.list({ title = 'Greets', items = { items(root)[1] } })

      list:command('add', { items = { items(root)[2] } })
      list:command('cursor', { index = 2 })

      assert.is_truthy(list:snapshot():find('cursor on .-a%.lua:2'))
      assert.is_truthy(list:snapshot():find('Greets', 1, true))

      local ok, err = pcall(list.command, list, 'cursor', { index = 9 })
      eq(false, ok)
      eq('no item 9 (the list has 2)', err)
    end)
  end)

  describe('panel', function()
    it('shows markdown and takes more of it', function()
      local panel = surfaces.panel({ title = 'Summary', markdown = 'first' })

      panel:command('write', { markdown = 'second', append = true })

      eq({ '# Summary', '', 'first', 'second' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      assert.is_truthy(panel:snapshot():find('panel "Summary" [ready]\nfirst\nsecond', 1, true))

      panel:command('close')
      eq('closed', panel.state)
      eq({}, surfaces.all())
    end)
  end)
end)

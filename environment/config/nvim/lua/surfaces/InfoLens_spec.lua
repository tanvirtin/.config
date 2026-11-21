local fs = require('core.system.fs')
local Lens = require('ui.Lens')
local lsp = require('core.editor.lsp')
local surfaces = require('surfaces')
local Window = require('core.editor.Window')
local InfoLens = require('surfaces.InfoLens')

local eq = assert.are.same

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('surfaces.InfoLens:', function()
  describe('compose', function()
    it('should trim a long hover and list a few places of use, with the rest counted', function()
      local hover, refs = {}, {}

      for i = 1, 10 do
        hover[i] = 'doc ' .. i
      end

      for i = 1, 7 do
        refs[i] = { path = '/w/a.lua', line = i }
      end

      local composed = InfoLens.compose(hover, refs)

      eq('doc 8', composed.lines[InfoLens.MAX_HOVER])
      eq('…', composed.lines[InfoLens.MAX_HOVER + 1])
      assert.is_truthy(vim.tbl_contains(composed.lines, '**Used in 7 places**'))
      eq('… 2 more', composed.lines[#composed.lines])

      local rows = vim.tbl_keys(composed.targets)

      eq(InfoLens.MAX_REFS, #rows)
      eq({ path = '/w/a.lua', line = 1 }, composed.targets[math.min(unpack(rows))])
    end)

    it('should say so when there is no hover or no use', function()
      local composed = InfoLens.compose({}, {})

      eq({ '*No hover information*', '', '*Not used anywhere else*' }, composed.lines)
      eq({}, composed.targets)
    end)

    it('should singularise one use', function()
      assert.is_truthy(
        vim.tbl_contains(InfoLens.compose({ 'x' }, { { path = '/w/a.lua', line = 1 } }).lines, '**Used in 1 place**')
      )
    end)
  end)

  describe('opening', function()
    local original, window, buffer, other, columns, lines

    local function float_of(surface)
      return surface._element:get_window().win_id
    end

    local function opened()
      local surface = surfaces.info()

      vim.wait(200, function()
        return surface:is_open() and surface._element:is_focused()
      end)

      return surface
    end

    before_each(function()
      columns, lines = vim.o.columns, vim.o.lines
      vim.o.columns, vim.o.lines = 120, 40
      vim.cmd('silent! tabonly!')
      vim.cmd('silent! only!')
      vim.cmd('enew!')

      window = Window.get_current()
      buffer = window:get_buffer()

      local text = {}

      for i = 1, 60 do
        text[i] = 'local function f' .. i .. '() end'
      end

      buffer:set_lines(text)
      vim.api.nvim_win_set_cursor(window.win_id, { 20, 15 })
      vim.wo.scrolloff = 0

      other = vim.fn.tempname() .. '.lua'
      vim.fn.writefile({ 'one', 'two', 'three', 'four' }, other)

      original = {}

      for _, name in ipairs({ 'request_all', 'clients', 'client', 'position_params', 'locations_to_items' }) do
        original[name] = lsp[name]
      end

      lsp.clients = function()
        return { { name = 'fake' } }
      end
      lsp.client = function()
        return { offset_encoding = 'utf-16' }
      end
      lsp.position_params = function()
        return { textDocument = { uri = 'file:///x' }, position = { line = 19, character = 15 } }
      end
      lsp.locations_to_items = function()
        return { { filename = other, lnum = 3 }, { filename = other, lnum = 4 } }
      end
      lsp.request_all = function(_, method, build, handler)
        build({ offset_encoding = 'utf-16' })

        if method == 'textDocument/hover' then
          handler({
            [1] = { result = { contents = { kind = 'markdown', value = '```lua\nfunction f20()\n```\nDoes f.' } } },
          })
        else
          handler({ [1] = { result = { { uri = 'file:///o' } } } })
        end
      end
    end)

    after_each(function()
      surfaces.close_all()

      for name, fn in pairs(original) do
        lsp[name] = fn
      end

      vim.o.columns, vim.o.lines = columns, lines
      vim.fn.delete(other)
    end)

    it('opens over reserved room above the cursor line, with a header, hover and the uses', function()
      local surface = opened()

      eq(true, surface:is_open())
      eq('info', surface.kind)

      local config = vim.api.nvim_win_get_config(float_of(surface))

      eq({ 'win', 'SW', window.win_id, 'none' }, { config.relative, config.anchor, config.win, config.border })
      eq({ 19, 0 }, config.bufpos)

      local marks = buffer:get_extmarks(Lens.NAMESPACE, 0, -1, { details = true })

      eq(1, #marks)
      assert.is_truthy(
        marks[1][4].virt_lines[1][1][1]:find('f20', 1, true) or marks[1][4].virt_lines[1][1][1]:find('f', 1, true)
      )

      local text = table.concat(surface._element:get_lines(), '\n')

      assert.is_truthy(text:find('function f20()', 1, true))
      assert.is_truthy(text:find('Used in 2 places', 1, true))
      assert.is_truthy(text:find(fs.display(other) .. ':3', 1, true))
      assert.is_truthy(surface:snapshot():find('Used in 2 places', 1, true))
    end)

    it('closes with q, giving the room and the focus back', function()
      local surface = opened()

      press('q')

      eq(false, surface:is_open())
      eq('closed', surface.state)
      eq(0, #buffer:get_extmarks(Lens.NAMESPACE))
      eq(window.win_id, Window.get_current().win_id)
    end)

    it('opens the reference under the cursor on <CR>, and closes', function()
      local surface = opened()
      local row

      for i, line in ipairs(surface._element:get_lines()) do
        if line:find(':4', 1, true) then row = i end
      end

      vim.api.nvim_win_set_cursor(float_of(surface), { row, 0 })
      press('<CR>')

      eq(false, surface:is_open())
      eq(vim.fn.resolve(other), vim.fn.resolve(vim.api.nvim_buf_get_name(0)))
      eq(4, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('does nothing on <CR> over the hover text', function()
      local surface = opened()

      vim.api.nvim_win_set_cursor(float_of(surface), { 1, 0 })
      press('<CR>')

      eq(true, surface:is_open())
    end)

    it('says when no language server is attached, and opens nothing', function()
      lsp.clients = function()
        return {}
      end

      local surface = surfaces.info()

      eq(false, surface:is_open())
      eq('closed', surface.state)
      eq(0, #buffer:get_extmarks(Lens.NAMESPACE))
    end)

    it('falls back to a panel when the window cannot hold it', function()
      vim.o.lines = 8

      local surface = surfaces.info()

      eq('closed', surface.state)
      eq(1, #vim.tbl_filter(function(s)
        return s.kind == 'panel'
      end, surfaces.all()))
    end)

    it('closes when the window it sits in is closed', function()
      vim.cmd('vsplit')

      local host = Window.get_current()
      local surface = surfaces.info({ window = host, line = 5 })

      eq(true, surface:is_open())
      host:close()
      vim.wait(200, function()
        return not surface:is_open()
      end)

      eq(false, surface:is_open())
    end)
  end)
end)

local spots = require('nvim_mcp.spots')

local eq = assert.are.same

describe('nvim_mcp.spots:', function()
  describe('parse', function()
    it('should read a bare path', function()
      eq({ path = 'a/b.lua' }, spots.parse('a/b.lua'))
    end)

    it('should read a line and a line range', function()
      eq({ path = 'a.lua', from = 42 }, spots.parse('a.lua:42'))
      eq({ path = 'a.lua', from = 42, to = 58 }, spots.parse('a.lua:42-58'))
    end)

    it('should read a symbol, including methods', function()
      eq({ path = 'a.lua', symbol = 'panes.show' }, spots.parse('a.lua#panes.show'))
      eq({ path = 'a.lua', symbol = 'Session:prompt' }, spots.parse('a.lua#Session:prompt'))
    end)

    it('should read the nvim:// links replies use', function()
      eq({ path = 'lua/a.lua', from = 7 }, spots.parse('nvim://file/lua/a.lua#L7'))
      eq({ path = 'lua/a.lua', from = 7, to = 9 }, spots.parse('nvim://file/lua/a.lua#L7-L9'))
      eq({ path = 'lua/a.lua', from = 7, to = 9 }, spots.parse('nvim://file/lua/a.lua#L7-9'))
    end)

    it('should take the previous file for #symbol and :line', function()
      eq({ path = 'a.lua', symbol = 'host' }, spots.parse('#host', 'a.lua'))
      eq({ path = 'a.lua', from = 3 }, spots.parse(':3', 'a.lua'))
    end)

    it('should explain a spot with no file', function()
      local spot, err = spots.parse('#host')

      eq(nil, spot)
      assert.is_truthy(err:find('no file', 1, true))
    end)
  end)

  describe('resolve', function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local M = {}', '', 'function M.go()', '  return 1', 'end' })
      vim.bo[buf].filetype = 'lua'
    end)

    after_each(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should give a symbol its whole definition', function()
      eq({ from = 3, to = 5 }, spots.resolve({ symbol = 'go' }, buf))
    end)

    it('should clamp lines to the buffer', function()
      eq({ from = 5, to = 5 }, spots.resolve({ from = 99 }, buf))
      eq({ from = 2, to = 5 }, spots.resolve({ from = 2, to = 99 }, buf))
      eq({ from = 1, to = 1 }, spots.resolve({}, buf))
    end)

    it('should say when a symbol is missing', function()
      local range, err = spots.resolve({ symbol = 'nope' }, buf)

      eq(nil, range)
      eq('no definition of nope', err)
    end)
  end)
end)

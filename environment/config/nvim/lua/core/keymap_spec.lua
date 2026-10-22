local keymap = require('core.keymap')

describe('keymap:', function()
  local original_set
  local calls

  before_each(function()
    calls = {}
    original_set = vim.keymap.set
    vim.keymap.set = function(mode, key, callback, opts)
      calls[#calls + 1] = { mode = mode, key = key, callback = callback, opts = opts }
    end
  end)

  after_each(function()
    vim.keymap.set = original_set
  end)

  describe('define', function()
    it('should define a key from "mode key" syntax', function()
      local cb = function() end
      keymap.define({ ['n <C-k>'] = cb })

      assert.are.equal(1, #calls)
      assert.are.equal('n', calls[1].mode)
      assert.are.equal('<C-k>', calls[1].key)
      assert.are.equal(cb, calls[1].callback)
    end)

    it('should define a key from a table config', function()
      local cb = function() end
      keymap.define({ { mode = 'n', key = '<C-j>', handler = cb, desc = 'down' } })

      assert.are.equal(1, #calls)
      assert.are.equal('n', calls[1].mode)
      assert.are.equal('<C-j>', calls[1].key)
      assert.are.equal(cb, calls[1].callback)
      assert.are.equal('down', calls[1].opts.desc)
    end)
  end)
  describe('buffer_set expr', function()
    it('passes expr through to a buffer-local mapping', function()
      keymap.buffer_set({ bufnr = 7 }, { mode = 'n', key = 'Q', expr = true }, function()
        return ''
      end)

      assert.are.same('Q', calls[1].key)
      assert.are.same(true, calls[1].opts.expr)
      assert.are.same(7, calls[1].opts.buffer)
    end)
  end)

  describe('feed', function()
    it('feeds keys with special notation decoded', function()
      local original = vim.api.nvim_feedkeys
      local fed

      vim.api.nvim_feedkeys = function(keys, mode)
        fed = { keys, mode }
      end

      keymap.feed('<C-x>')

      vim.api.nvim_feedkeys = original
      assert.are.same({ vim.keycode('<C-x>'), 'n' }, fed)
    end)
  end)
end)

describe('keymap.count:', function()
  it('reads the count typed before a mapping, one when none was', function()
    local counts = {}

    vim.keymap.set('n', '<F9>', function()
      counts[#counts + 1] = keymap.count()
    end)

    vim.api.nvim_feedkeys('3' .. vim.keycode('<F9>'), 'x', false)
    vim.api.nvim_feedkeys(vim.keycode('<F9>'), 'x', false)
    vim.keymap.del('n', '<F9>')

    assert.are.same({ 3, 1 }, counts)
  end)
end)

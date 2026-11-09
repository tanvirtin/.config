local settings = require('harness.settings')
local global_keys = require('harness.ui.global_keys')

local eq = assert.are.same

local function with_keys(section, overrides, fn)
  local before = vim.deepcopy(settings.keymaps:get(section))

  settings.keymaps:assign({ [section] = overrides })

  local ok, err = pcall(fn)

  settings.keymaps:set(section, before)

  if not ok then error(err, 0) end
end

describe('keys the harness names on screen:', function()
  after_each(function()
    pcall(vim.keymap.del, 'n', '<leader>zq')
    global_keys.forget()
  end)

  it('names the key that opens the sessions as the user mapped it, or the command when it is not mapped', function()
    eq(':Harness switch', global_keys.sessions())

    global_keys.forget()
    vim.keymap.set('n', '<leader>zq', '<Cmd>lua require("harness").switch()<CR>')

    eq('<leader>zq', global_keys.sessions())

    global_keys.forget()
    vim.keymap.del('n', '<leader>zq')
    vim.keymap.set('n', '<leader>zq', '<Cmd>Harness switch<CR>')

    eq('<leader>zq', global_keys.sessions())
  end)

  it('shows that key, and the keys from the settings, in the transcript winbar', function()
    vim.keymap.set('n', '<leader>zq', '<Cmd>lua require("harness").switch()<CR>')

    with_keys('transcript', { help = 'g!' }, function()
      local hints = require('harness.ui.winbar').hints()

      assert.truthy(hints:find('<leader>zq', 1, true))
      assert.truthy(hints:find('g!', 1, true))
      assert.is_nil(hints:find('<leader>.', 1, true))
    end)
  end)

  it('lists the sessions picker keys from the settings', function()
    with_keys('sessions', { fork = '<C-k>', delete = '<C-d>' }, function()
      local SessionsView = require('harness.ui.SessionsView')
      local shown = vim.tbl_map(function(hint)
        return hint[1]
      end, SessionsView.hints())

      assert.is_true(vim.tbl_contains(shown, '<C-k>'))
      assert.is_true(vim.tbl_contains(shown, '<C-d>'))
      assert.is_false(vim.tbl_contains(shown, '<C-f>'))
    end)
  end)

  it('names the permissions panel keys, including the mode key, from the settings', function()
    with_keys('transcript', { cycle_mode = '<C-m>' }, function()
      with_keys('permissions', { act = 'x' }, function()
        local footer = require('harness.ui.PermissionsView').footer()

        assert.truthy(footer:find('x revoke or delete', 1, true))
        assert.truthy(footer:find('<C-m> mode', 1, true))
        assert.is_nil(footer:find('<S-Tab>', 1, true))
      end)
    end)
  end)
end)

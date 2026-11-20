local router = require('harness.cli.router')

local eq = assert.are.same

describe('harness.cli.router:', function()
  after_each(function()
    router.setup()
  end)

  it('registers the one :Harness command', function()
    router.setup()

    local registered = vim.api.nvim_get_commands({})

    eq(
      { 'Harness' },
      vim.tbl_map(function(command)
        return command.name
      end, router.commands())
    )
    eq('Harness', registered.Harness.name)

    for name in pairs(registered) do
      assert.is_false(name ~= 'Harness' and name:find('^Harness') ~= nil, name .. ' should be a subcommand of :Harness')
    end
  end)

  it('removes its command and shutdown hook on teardown', function()
    router.setup()
    router.teardown()

    local registered = vim.api.nvim_get_commands({})

    assert.is_nil(registered.Harness)
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = 'harness' }))
  end)

  it('runs a command by name, and refuses unknown ones', function()
    assert.is_nil(router.execute('Harness', { args = 'cancel', range = 0 }))

    assert.has_error(function()
      router.execute('HarnessNope')
    end)
  end)

  it('gives every command a name, a description and an execute function', function()
    for _, command in ipairs(router.commands()) do
      eq('string', type(command.name))
      eq('string', type(command.opts.desc))
      eq('function', type(command.execute))
    end
  end)
end)

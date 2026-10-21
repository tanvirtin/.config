local router = require('harness.cli.router')

local eq = assert.are.same

describe('harness.cli.router:', function()
  after_each(function()
    router.setup()
  end)

  it('registers one user command per command module', function()
    router.setup()

    local registered = vim.api.nvim_get_commands({})

    for _, command in ipairs(router.commands()) do
      eq(command.name, registered[command.name].name)
    end

    eq(
      { 'Harness', 'HarnessNew', 'HarnessSessions', 'HarnessStats', 'HarnessCancel', 'HarnessClear' },
      vim.tbl_map(function(command)
        return command.name
      end, router.commands())
    )
  end)

  it('removes its commands and shutdown hook on teardown', function()
    router.setup()
    router.teardown()

    local registered = vim.api.nvim_get_commands({})

    assert.is_nil(registered.Harness)
    assert.is_nil(registered.HarnessClear)
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = 'harness' }))
  end)

  it('runs a command by name, and refuses unknown ones', function()
    local script = require('nvim_mcp.script')
    local original = script.clear

    script.clear = function()
      return 3
    end

    eq(3, router.execute('HarnessClear'))
    script.clear = original

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

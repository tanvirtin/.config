local help = require('harness.ui.help')

local eq = assert.are.same

describe('harness.ui.help:', function()
  local bindings = {
    { 'gd', function() end, 'Open the edit' },
    { { 'i', 'a' }, function() end, 'Write' },
    { '<C-c>', function() end, 'Interrupt | stop' },
    { 'x', function() end },
  }

  it('sorts the keys and skips what has no description', function()
    eq(
      { '<C-c>', 'gd', 'i a' },
      vim.tbl_map(function(row)
        return row.lhs
      end, help.rows(bindings))
    )
  end)

  it('renders a markdown table with escaped bars', function()
    local lines = vim.split(help.markdown(bindings), '\n')

    eq('| Key | Does |', lines[1])
    eq('| `<C-c>` | Interrupt \\| stop |', lines[3])
    eq(5, #lines)
  end)
end)

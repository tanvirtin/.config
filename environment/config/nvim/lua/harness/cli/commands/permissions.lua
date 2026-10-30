local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessPermissions',
  opts = { desc = 'Show the current Harness session\'s permissions: grants, saved rules and decisions' },
  execute = function()
    return commands.permissions()
  end,
}

local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessChanges',
  opts = { desc = 'Open every file the current Harness session changed in vgit' },
  execute = function()
    return commands.changes()
  end,
}

local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessCancel',
  opts = { desc = 'Stop the running Harness turn' },
  execute = function()
    return commands.cancel()
  end,
}

local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessSessions',
  opts = { desc = 'Open, start or delete this directory\'s Harness sessions' },
  execute = function()
    return commands.sessions()
  end,
}

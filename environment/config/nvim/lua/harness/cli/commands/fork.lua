local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessFork',
  opts = { desc = 'Fork the session from the reply under the cursor in its transcript' },
  execute = function()
    return commands.fork()
  end,
}

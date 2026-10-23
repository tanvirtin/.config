local lazy = require('core.lazy')

local surfaces = lazy('surfaces')
local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessStats',
  opts = { desc = 'Tokens per Harness session, and what compact tool output saved' },
  execute = function()
    return surfaces.panel({ title = 'Harness tokens', lines = commands.stats_lines() })
  end,
}

local lazy = require('core.lazy')

local console = lazy('core.console')
local script = lazy('nvim_mcp.script')

return {
  name = 'HarnessClear',
  opts = { desc = 'Remove the autocmds, keymaps, windows, timers and highlights Harness scripts created' },
  execute = function()
    local count = script.clear()

    console.notify_now(string.format('Harness: removed %d things scripts created', count))

    return count
  end,
}

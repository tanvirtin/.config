local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessRevert',
  opts = {
    nargs = '?',
    complete = function()
      return { 'edit', 'turn', 'session' }
    end,
    desc = 'Revert the agent\'s edit, turn or session after a preview in vgit',
  },
  execute = function(args)
    return commands.revert(args.args)
  end,
}

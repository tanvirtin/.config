local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessQuickfix',
  opts = {
    nargs = '?',
    complete = function()
      return { 'edit', 'turn', 'session' }
    end,
    desc = 'Send the agent\'s edits (of an edit, a turn or the session) to the quickfix list',
  },
  execute = function(args)
    return commands.quickfix(args.args)
  end,
}

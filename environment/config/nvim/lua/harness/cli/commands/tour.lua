local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessTour',
  opts = {
    nargs = '*',
    complete = function()
      return { 'changes', 'turn', 'session', 'next', 'prev', 'stop' }
    end,
    desc = 'Walk through the agent\'s changes, or ask for a guided tour of the code (`:HarnessTour how does login work`)',
  },
  execute = function(args)
    return commands.tour(args.args)
  end,
}

local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessTour',
  opts = {
    nargs = '?',
    complete = function()
      return { 'changes', 'turn', 'session', 'next', 'prev', 'stop', 'resume' }
    end,
    desc = 'Drive a tour (next, prev, stop, resume), or walk through the agent\'s own changes; ask your session for any other tour',
  },
  execute = function(args)
    return commands.tour(args.args)
  end,
}

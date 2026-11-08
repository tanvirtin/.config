local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessWalkthrough',
  opts = {
    nargs = '?',
    complete = function()
      return { 'changes', 'turn', 'session', 'next', 'prev', 'overview', 'findings', 'submit', 'stop', 'resume' }
    end,
    desc = 'Drive a walkthrough (next, prev, overview, findings, submit, stop, resume), or walk through the agent\'s own changes; ask your session for any other walkthrough',
  },
  execute = function(args)
    return commands.walkthrough(args.args)
  end,
}

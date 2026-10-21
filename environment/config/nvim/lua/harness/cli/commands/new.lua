local lazy = require('core.lazy')

local agent = lazy('harness.agent')
local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessNew',
  opts = {
    nargs = '?',
    complete = function()
      return agent.names()
    end,
    desc = 'Open a new Harness session',
  },
  execute = function(args)
    return commands.new(args.args ~= '' and args.args or nil)
  end,
}

local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'Harness',
  opts = { nargs = '+', range = true, desc = 'Ask an agent (over ACP) to work in this editor' },
  execute = function(args)
    return commands.run(args.args, nil, args.range > 0 and { args.line1, args.line2 } or nil)
  end,
}

local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessDock',
  opts = {
    nargs = '?',
    complete = function()
      return { 'open', 'compact', 'half', 'zoom', 'close' }
    end,
    desc = 'Dock the session on the right, or set its width (compact, half), zoom it full screen, or close it',
  },
  execute = function(args)
    return commands.dock(args.args)
  end,
}

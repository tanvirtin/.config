local lazy = require('core.lazy')

local commands = lazy('harness.ui.commands')

return {
  name = 'HarnessTranscript',
  opts = {
    nargs = '?',
    complete = function()
      return { 'expand', 'right' }
    end,
    desc = 'Tile the transcript in focus: expand it wider, or move it to the right at its compact width',
  },
  execute = function(args)
    return commands.transcript(args.args)
  end,
}

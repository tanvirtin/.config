local editor = require('core.editor')
local schema = require('nvim_mcp.schema')
local script = require('nvim_mcp.script')

return {
  {
    name = 'lua',
    risk = 'exec',
    summary = 'Run a Lua script inside the editor with full vim.* access, for anything the other tools do not cover. Returns printed output and returned values; errors come back with a traceback. Globals persist between scripts. Stops after timeout_ms (default 10000).',
    params = {
      { name = 'code', type = schema.str() },
      { name = 'timeout_ms', type = schema.int(), optional = true },
    },
    fn = function(args)
      return script.run(args.code, args.timeout_ms)
    end,
  },
  {
    name = 'ex',
    risk = 'exec',
    summary = 'Run an Ex command (for example "messages" or "%s/a/b/g") and return its output.',
    params = { { name = 'command', type = schema.str() } },
    fn = function(args)
      return editor.exec(args.command)
    end,
  },
}

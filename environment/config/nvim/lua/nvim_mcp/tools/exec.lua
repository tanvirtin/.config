local schema = require('nvim_mcp.schema')
local script = require('nvim_mcp.script')

return {
  {
    name = 'lua',
    risk = 'exec',
    summary = 'Run a multi-line Lua script inside the editor with full vim.* access: build quickfix lists, floats, scratch buffers, extmarks, or anything else. Returns printed output and returned values; errors come back with a traceback. Globals persist between scripts (in a scratch environment, not _G). Callbacks a script registers (autocmds, keymaps, timers, decoration providers) are disabled on their first error, which is reported with the next script; :HarnessClear removes everything scripts created. Stops after timeout_ms (default 10000).',
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
      return vim.api.nvim_exec2(args.command, { output = true }).output
    end,
  },
}

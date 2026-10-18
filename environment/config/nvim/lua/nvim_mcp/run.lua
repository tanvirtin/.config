local info = debug.getinfo(1, 'S')
local script = info.source:sub(1, 1) == '@' and info.source:sub(2) or info.source
local dir = vim.fs.dirname(script)
local lua_root = vim.fs.normalize(dir .. '/..')

package.path = table.concat({
  lua_root .. '/?.lua',
  lua_root .. '/?/init.lua',
  package.path,
}, ';')

require('nvim_mcp.server').main(_G.arg and _G.arg[1] or vim.env.NVIM_MCP_ADDR)

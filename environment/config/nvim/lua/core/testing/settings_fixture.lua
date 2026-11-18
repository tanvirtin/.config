local settings = require('core.settings')
local Config = require('core.Config')

local vgit_lua = (os.getenv('VGIT_DIR') or (os.getenv('HOME') .. '/workspace/vgit.nvim')) .. '/lua/'

if not package.path:find(vgit_lua, 1, true) then
  package.path = vgit_lua .. '?.lua;' .. vgit_lua .. '?/init.lua;' .. package.path
end

local function register_fixture_settings()
  settings.register(
    'signs',
    Config({
      priority = 10,
      definitions = {
        GitSignsAdd = {
          texthl = 'GitSignsAdd',
          text = '┃',
        },
        GitSignsDelete = {
          texthl = 'GitSignsDelete',
          text = '┃',
        },
        GitSignsChange = {
          texthl = 'GitSignsChange',
          text = '┃',
        },
        GitSignsAddLn = {
          linehl = 'GitSignsAddLn',
          text = '',
        },
        GitSignsDeleteLn = {
          linehl = 'GitSignsDeleteLn',
          text = '',
        },
      },
      usage = {
        scene = {
          add = 'GitSignsAddLn',
          remove = 'GitSignsDeleteLn',
        },
        main = {
          add = 'GitSignsAdd',
          remove = 'GitSignsDelete',
          change = 'GitSignsChange',
        },
      },
    })
  )
  settings.register(
    'symbols',
    Config({
      void = '⣿',
      open = '',
      close = '',
    })
  )
end

return function()
  register_fixture_settings()
  return true
end

local keymap = require('core.keymap')

local global_keys = {}

global_keys.SESSIONS = 'HarnessSessions'

local cache = {}

function global_keys.of(command)
  if cache[command] == nil then cache[command] = keymap.lhs_of(command) or false end

  return cache[command] or (':' .. command)
end

function global_keys.sessions()
  return global_keys.of(global_keys.SESSIONS)
end

function global_keys.forget()
  cache = {}
end

return global_keys

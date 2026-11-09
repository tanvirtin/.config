local keymap = require('core.keymap')

local global_keys = {}

global_keys.SWITCH = { 'harness").switch', 'harness\').switch', 'Harness switch' }
global_keys.FALLBACK = ':Harness switch'

local cache = {}

function global_keys.of(needles, fallback)
  local key = table.concat(needles, '\0')

  if cache[key] == nil then
    cache[key] = false

    for _, needle in ipairs(needles) do
      local lhs = keymap.lhs_of(needle)

      if lhs then
        cache[key] = lhs
        break
      end
    end
  end

  return cache[key] or fallback
end

function global_keys.sessions()
  return global_keys.of(global_keys.SWITCH, global_keys.FALLBACK)
end

function global_keys.forget()
  cache = {}
end

return global_keys

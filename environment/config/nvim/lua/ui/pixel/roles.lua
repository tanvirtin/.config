local markup = require('ui.markup')
local Bitmap = require('ui.pixel.Bitmap')
local highlight = require('core.editor.highlight')

local roles = {}

roles.FALLBACK = 0xffffff

local function group_spec(name)
  local group = markup.group(name)

  return group and highlight.get_hl_by_name(group) or {}
end

function roles.resolve(name)
  if type(name) == 'number' then return name end

  if type(name) == 'table' then return name[1] * 65536 + name[2] * 256 + name[3] end

  if type(name) ~= 'string' then return roles.FALLBACK end

  local hex = name:match('^#(%x%x%x%x%x%x)$')

  if hex then return tonumber(hex, 16) end

  local spec = group_spec(name)

  return spec.fg or spec.bg or roles.FALLBACK
end

function roles.background(name)
  if type(name) ~= 'string' or name:match('^#%x%x%x%x%x%x$') then return roles.resolve(name) end

  local spec = group_spec(name)

  return spec.bg or highlight.get_hl_by_name('Normal').bg or roles.FALLBACK
end

function roles.rgb(name)
  if type(name) == 'table' then return name end

  return Bitmap.rgb(roles.resolve(name))
end

return roles

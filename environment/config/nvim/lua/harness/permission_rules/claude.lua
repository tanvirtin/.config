local permission = require('harness.types.permission')
local json_text = require('harness.permission_rules.json_text')

local claude = {}

claude.KEY = 'permissions'

function claude.parse(text)
  local tool, content = text:match('^([^%(]+)%((.*)%)$')

  if not tool then return text, nil end

  return tool, content ~= '' and content or nil
end

function claude.read(text)
  local ok, decoded = pcall(vim.json.decode, text)

  if not ok or type(decoded) ~= 'table' then return nil, 'the file is not valid JSON' end

  local section = type(decoded[claude.KEY]) == 'table' and decoded[claude.KEY] or {}
  local out = {}

  for _, behavior in ipairs({ permission.BEHAVIOR.allow, permission.BEHAVIOR.ask, permission.BEHAVIOR.deny }) do
    for _, rule in ipairs(type(section[behavior]) == 'table' and section[behavior] or {}) do
      if type(rule) == 'string' then out[#out + 1] = { behavior = behavior, text = rule } end
    end
  end

  return out
end

function claude.remove(text, behavior, rule)
  return json_text.remove(text, { claude.KEY, behavior }, rule)
end

return claude

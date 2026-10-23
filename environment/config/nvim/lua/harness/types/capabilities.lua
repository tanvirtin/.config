local dataclass = require('core.dataclass')

local capabilities = {}

capabilities.NAMES = {
  'load',
  'resume',
  'fork',
  'fork_at_message',
  'list',
  'close',
  'delete',
  'steer',
  'system_prompt',
  'embedded_context',
  'images',
  'audio',
}

local fields = {}

for _, name in ipairs(capabilities.NAMES) do
  fields[name] = { type = 'boolean', required = true }
end

capabilities.Capabilities = dataclass.define('Capabilities', fields)

function capabilities.new(values)
  local out = {}

  for _, name in ipairs(capabilities.NAMES) do
    out[name] = type(values) == 'table' and values[name] == true or false
  end

  return capabilities.Capabilities(out)
end

return capabilities

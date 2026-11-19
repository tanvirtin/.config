local dataclass = require('core.dataclass')

local config = {}

config.MODE = 'mode'

config.Choice = dataclass.define('ConfigChoice', {
  value = { type = 'string', required = true },
  name = { type = 'string' },
  description = { type = 'string' },
})

config.Option = dataclass.define('ConfigOption', {
  id = { type = 'string', required = true },
  name = { type = 'string' },
  description = { type = 'string' },
  category = { type = 'string' },
  kind = { type = 'string' },
  current = { type = { 'string', 'boolean', 'number' } },
  choices = {
    type = 'table',
    default = function()
      return {}
    end,
  },
})

function config.find(options, key)
  for _, option in ipairs(options or {}) do
    if option.id == key then return option end
  end

  for _, option in ipairs(options or {}) do
    if option.category == key then return option end
  end
end

function config.current(option)
  for _, choice in ipairs(option and option.choices or {}) do
    if choice.value == option.current then return choice end
  end
end

return config

local config = require('harness.types.config')
local session = require('harness.types.session')

local acp_config = {}

acp_config.MODES = 'acp:modes'

local function str(value)
  return type(value) == 'string' and value or nil
end

local function choices(list)
  local out = {}

  for _, choice in ipairs(type(list) == 'table' and list or {}) do
    if type(choice) == 'table' and type(choice.options) == 'table' then
      vim.list_extend(out, choices(choice.options))
    elseif type(choice) == 'table' and str(choice.value) then
      out[#out + 1] =
        config.Choice({ value = choice.value, name = str(choice.name), description = str(choice.description) })
    end
  end

  return out
end

local function has_mode(options)
  return config.find(options, config.MODE) ~= nil
end

function acp_config.options(config_options, modes)
  local out = {}

  for _, option in ipairs(type(config_options) == 'table' and config_options or {}) do
    if type(option) == 'table' and str(option.id) then
      local current = option.currentValue
      local typed = type(current) == 'string' or type(current) == 'boolean' or type(current) == 'number'

      out[#out + 1] = config.Option({
        id = option.id,
        name = str(option.name),
        description = str(option.description),
        category = str(option.category),
        kind = str(option.type),
        current = typed and current or nil,
        choices = choices(option.options),
      })
    end
  end

  if type(modes) == 'table' and type(modes.availableModes) == 'table' and not has_mode(out) then
    out[#out + 1] = config.Option({
      id = acp_config.MODES,
      name = 'Mode',
      category = config.MODE,
      kind = 'select',
      current = str(modes.currentModeId),
      choices = vim.tbl_map(
        function(mode)
          return config.Choice({ value = mode.id, name = str(mode.name), description = str(mode.description) })
        end,
        vim.tbl_filter(function(mode)
          return type(mode) == 'table' and str(mode.id) ~= nil
        end, modes.availableModes)
      ),
    })
  end

  return out
end

function acp_config.opened(result)
  result = type(result) == 'table' and result or {}

  return session.Opened({
    id = str(result.sessionId),
    options = acp_config.options(result.configOptions, result.modes),
  })
end

function acp_config.stored(entry)
  return session.Stored({ id = entry.sessionId, title = str(entry.title), updated_at = str(entry.updatedAt) })
end

return acp_config

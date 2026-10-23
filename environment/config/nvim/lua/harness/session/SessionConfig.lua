local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local events = lazy('harness.types.events')

local SessionConfig = Object:extend()

SessionConfig.MODE = 'mode'

function SessionConfig:constructor(session)
  return { session = session }
end

function SessionConfig.choices(option)
  local out = {}

  for _, choice in ipairs(option.options or {}) do
    if type(choice) == 'table' and choice.options then
      vim.list_extend(out, choice.options)
    else
      out[#out + 1] = choice
    end
  end

  return out
end

local function find(options, key)
  for _, option in ipairs(options) do
    if option.id == key then return option end
  end

  for _, option in ipairs(options) do
    if option.category == key then return option end
  end
end

function SessionConfig:_changed()
  self.session:_notify({ kind = events.NOTICE.config })
end

function SessionConfig:apply(event)
  local session = self.session
  local K = events.KIND

  if event.kind == K.config then
    session.options = event.options
  elseif event.kind == K.mode then
    if session.modes then session.modes.currentModeId = event.id end

    for _, option in ipairs(session.options) do
      if option.category == SessionConfig.MODE or option.id == SessionConfig.MODE then
        option.currentValue = event.id
      end
    end
  elseif event.kind == K.commands then
    session.commands = event.commands
  end
end

function SessionConfig:configure(result)
  if type(result) ~= 'table' then return end

  if type(result.configOptions) == 'table' then self.session.options = result.configOptions end
  if type(result.modes) == 'table' then self.session.modes = result.modes end

  self:_changed()
end

function SessionConfig:option(key)
  return find(self.session.options, key)
end

function SessionConfig:choice(key)
  local option = self:option(key)

  if not option then return nil end

  for _, choice in ipairs(SessionConfig.choices(option)) do
    if choice.value == option.currentValue then return choice end
  end
end

function SessionConfig:mode()
  local choice = self:choice(SessionConfig.MODE)

  if choice then return { id = choice.value, name = choice.name } end

  local modes = self.session.modes

  if not modes then return nil end

  for _, mode in ipairs(modes.availableModes or {}) do
    if mode.id == modes.currentModeId then return { id = mode.id, name = mode.name } end
  end
end

function SessionConfig:mode_choices()
  local option = self:option(SessionConfig.MODE)

  if option then
    return vim.tbl_map(function(choice)
      return { id = choice.value, name = choice.name, description = choice.description }
    end, SessionConfig.choices(option))
  end

  return vim.tbl_map(function(mode)
    return { id = mode.id, name = mode.name, description = mode.description }
  end, (self.session.modes or {}).availableModes or {})
end

function SessionConfig:set_option(id, value)
  local session = self.session

  return async.run(function()
    local result = session.connection:set_config(session.id, id, value)

    if type(result) == 'table' and type(result.configOptions) == 'table' and #result.configOptions > 0 then
      session.options = result.configOptions
    else
      local option = find(session.options, id)
      if option then option.currentValue = value end
    end

    self:_changed()

    return result
  end)
end

function SessionConfig:set_mode(id)
  local session = self.session
  local option = self:option(SessionConfig.MODE)

  if option then return session:set_option(option.id, id) end

  return async.run(function()
    local result = session.connection:set_mode(session.id, id)

    if session.modes then session.modes.currentModeId = id end
    self:_changed()

    return result
  end)
end

function SessionConfig:cycle_mode()
  local session = self.session
  local available = session:mode_choices()
  local current = session:mode()

  if #available == 0 then return nil end

  local index = 0

  for i, mode in ipairs(available) do
    if current and mode.id == current.id then index = i end
  end

  return session:set_mode(available[index % #available + 1].id)
end

return SessionConfig

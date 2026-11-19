local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local config = lazy('harness.types.config')
local events = lazy('harness.types.events')

local SessionConfig = Object:extend()

SessionConfig.MODE = 'mode'

function SessionConfig:constructor(session)
  return { session = session }
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
    local option = self:option(SessionConfig.MODE)

    if option then option.current = event.id end
  elseif event.kind == K.commands then
    session.commands = event.commands
  end
end

function SessionConfig:configure(options)
  if type(options) ~= 'table' or #options == 0 then return end

  self.session.options = options
  self:_changed()
end

function SessionConfig:option(key)
  return config.find(self.session.options, key)
end

function SessionConfig:choice(key)
  return config.current(self:option(key))
end

function SessionConfig:mode()
  local choice = self:choice(SessionConfig.MODE)

  return choice and { id = choice.value, name = choice.name } or nil
end

function SessionConfig:mode_choices()
  local option = self:option(SessionConfig.MODE)

  return vim.tbl_map(function(choice)
    return { id = choice.value, name = choice.name, description = choice.description }
  end, option and option.choices or {})
end

function SessionConfig:set_option(id, value)
  local session = self.session

  return async.run(function()
    local options = session.connection:set_option(session.id, id, value)

    if options then
      session.options = options
    else
      local option = config.find(session.options, id)

      if option then option.current = value end
    end

    self:_changed()

    return options
  end)
end

function SessionConfig:set_mode(id)
  local option = self:option(SessionConfig.MODE)

  if not option then return nil end

  return self.session:set_option(option.id, id)
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

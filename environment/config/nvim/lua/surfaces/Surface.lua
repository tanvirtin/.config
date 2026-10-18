local Object = require('core.Object')
local schema = require('nvim_mcp.schema')

local Surface = Object:extend()

function Surface:constructor(opts)
  return {
    id = nil,
    kind = opts.kind,
    title = opts.title or opts.kind,
    owner = opts.owner,
    state = 'opening',
    _listeners = {},
    _view = nil,
  }
end

Surface.COMMANDS = {
  close = {
    summary = 'Close it.',
    params = {},
    run = function(self)
      self:close()
    end,
  },
}

function Surface:set_state(state)
  if self.state == state then return end

  self.state = state
  self:emit('state', state)
end

function Surface:commands()
  local out, seen = {}, {}
  local class = getmetatable(self)

  while class do
    for name, command in pairs(rawget(class, 'COMMANDS') or {}) do
      if not seen[name] then
        seen[name] = true
        out[#out + 1] = { name = name, summary = command.summary, params = command.params }
      end
    end

    class = rawget(class, 'super')
  end

  table.sort(out, function(a, b)
    return a.name < b.name
  end)

  return out
end

local function find_command(self, name)
  local class = getmetatable(self)

  while class do
    local command = (rawget(class, 'COMMANDS') or {})[name]
    if command then return command end
    class = rawget(class, 'super')
  end
end

function Surface:command(name, args)
  local command = find_command(self, name)

  if not command then
    local names = vim.tbl_map(function(c)
      return c.name
    end, self:commands())
    error(string.format('%s has no command %s (commands: %s)', self.kind, tostring(name), table.concat(names, ', ')), 0)
  end

  if not self:is_open() and name ~= 'close' then error(self.id .. ' is closed', 0) end

  local ok, coerced = schema.validate(schema.model(command.params), args or {})

  if not ok then error('invalid arguments for ' .. name .. ': ' .. schema.format_errors(coerced), 0) end

  return command.run(self, coerced)
end

function Surface:usage()
  return table.concat(
    vim.tbl_map(function(command)
      local args = vim.tbl_map(function(field)
        return field.name .. (field.optional and '?' or '')
      end, command.params)

      return string.format('%s(%s)', command.name, table.concat(args, ', '))
    end, self:commands()),
    ' '
  )
end

function Surface:open()
  error('Surface:open() must be implemented by ' .. tostring(self.kind))
end

function Surface:snapshot()
  error('Surface:snapshot() must be implemented by ' .. tostring(self.kind))
end

function Surface:is_open()
  return self._view ~= nil and not self._view:is_destroyed()
end

function Surface:close()
  if self._view then self._view:destroy() end

  self:set_state('closed')
  self:emit('close')
end

function Surface:on(event, fn)
  self._listeners[event] = self._listeners[event] or {}
  table.insert(self._listeners[event], fn)

  return self
end

function Surface:emit(event, ...)
  for _, fn in ipairs(self._listeners[event] or {}) do
    local ok, err = pcall(fn, ...)

    if not ok then
      vim.notify('surface ' .. tostring(self.id) .. ' ' .. event .. ': ' .. tostring(err), vim.log.levels.WARN)
    end
  end
end

function Surface:describe()
  return string.format(
    '%s %s "%s" [%s]%s commands: %s',
    self.id,
    self.kind,
    self.title,
    self.state,
    self.owner and (' by ' .. self.owner) or '',
    self:usage()
  )
end

return Surface

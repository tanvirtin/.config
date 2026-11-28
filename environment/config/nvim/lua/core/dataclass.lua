local dataclass = {}

local function allowed_types(spec)
  if spec.type == nil or spec.type == 'any' then return false end

  local allowed = {}

  for _, name in ipairs(type(spec.type) == 'table' and spec.type or { spec.type }) do
    allowed[name] = true
  end

  return allowed
end

local function describe(spec)
  return type(spec.type) == 'table' and table.concat(spec.type, '|') or tostring(spec.type)
end

function dataclass.enum(values)
  local enum = {}

  for _, value in ipairs(values) do
    enum[value] = value
  end

  return setmetatable(enum, {
    __index = function(_, key)
      error(string.format('unknown enum value "%s"', tostring(key)), 2)
    end,
  })
end

function dataclass.is_member(enum, value)
  return rawget(enum, value) ~= nil
end

function dataclass.define(name, schema)
  local class = { __name = name, schema = schema }
  local required, defaults, types = {}, {}, {}

  for key, spec in pairs(schema) do
    if spec.required then required[#required + 1] = key end
    if spec.default ~= nil then defaults[#defaults + 1] = key end

    types[key] = allowed_types(spec)
  end

  class.__index = class

  function class.new(fields)
    local instance = {}

    for key, value in pairs(fields or {}) do
      local allowed = types[key]

      if allowed == nil then error(string.format('%s: unknown field "%s"', name, tostring(key)), 3) end

      local spec = schema[key]

      if allowed and not allowed[type(value)] then
        error(string.format('%s.%s: expected %s, got %s', name, key, describe(spec), type(value)), 3)
      end

      if spec.enum and not dataclass.is_member(spec.enum, value) then
        error(string.format('%s.%s: "%s" is not one of its values', name, key, tostring(value)), 3)
      end

      instance[key] = value
    end

    for _, key in ipairs(defaults) do
      if instance[key] == nil then
        local default = schema[key].default
        instance[key] = type(default) == 'function' and default() or default
      end
    end

    for _, key in ipairs(required) do
      if instance[key] == nil then error(string.format('%s: missing required field "%s"', name, key), 3) end
    end

    return setmetatable(instance, class)
  end

  function class.is(value)
    return getmetatable(value) == class
  end

  return setmetatable(class, {
    __call = function(_, fields)
      return class.new(fields)
    end,
  })
end

return dataclass

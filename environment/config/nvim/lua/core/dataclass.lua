local dataclass = {}

local function type_ok(spec, value)
  if spec.type == nil or spec.type == 'any' then return true end

  if type(spec.type) == 'table' then
    for _, allowed in ipairs(spec.type) do
      if type(value) == allowed then return true end
    end

    return false
  end

  return type(value) == spec.type
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

  class.__index = class

  function class.new(fields)
    fields = fields or {}

    for key in pairs(fields) do
      if schema[key] == nil then error(string.format('%s: unknown field "%s"', name, tostring(key)), 3) end
    end

    local instance = {}

    for key, spec in pairs(schema) do
      local value = fields[key]

      if value == nil and spec.default ~= nil then
        value = type(spec.default) == 'function' and spec.default() or spec.default
      end

      if value == nil then
        if spec.required then error(string.format('%s: missing required field "%s"', name, key), 3) end
      else
        if not type_ok(spec, value) then
          error(string.format('%s.%s: expected %s, got %s', name, key, describe(spec), type(value)), 3)
        end

        if spec.enum and not dataclass.is_member(spec.enum, value) then
          error(string.format('%s.%s: "%s" is not one of its values', name, key, tostring(value)), 3)
        end
      end

      instance[key] = value
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

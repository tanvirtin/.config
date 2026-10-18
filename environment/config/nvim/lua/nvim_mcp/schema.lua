local schema = {}

local function with_description(t, opts)
  t.description = opts and opts.description

  return t
end

function schema.any()
  return { kind = 'any' }
end

function schema.bool(opts)
  return with_description({ kind = 'bool' }, opts)
end

function schema.int(opts)
  return with_description({ kind = 'int' }, opts)
end

function schema.float(opts)
  return with_description({ kind = 'float' }, opts)
end

function schema.str(opts)
  return with_description({ kind = 'str' }, opts)
end

function schema.literal(values, opts)
  return with_description({ kind = 'literal', values = values }, opts)
end

function schema.list(item, opts)
  return with_description({ kind = 'list', item = item }, opts)
end

function schema.dict(value, opts)
  return with_description({ kind = 'dict', value = value }, opts)
end

function schema.model(fields)
  return { kind = 'model', fields = fields }
end

local function fail(errors, path, message)
  errors[#errors + 1] = { path = path, message = message }

  return false
end

local function child(path, key)
  return path == '' and tostring(key) or (path .. '.' .. tostring(key))
end

local validate

local VALIDATORS = {
  any = function(_, value)
    return true, value
  end,

  bool = function(_, value, path, errors)
    if type(value) == 'boolean' then return true, value end
    if value == 'true' or value == 'false' then return true, value == 'true' end

    return fail(errors, path, 'expected a boolean')
  end,

  int = function(_, value, path, errors)
    local n = tonumber(value)

    if type(n) ~= 'number' or math.floor(n) ~= n then return fail(errors, path, 'expected an integer') end

    return true, n
  end,

  float = function(_, value, path, errors)
    local n = tonumber(value)

    if type(n) ~= 'number' then return fail(errors, path, 'expected a number') end

    return true, n
  end,

  str = function(_, value, path, errors)
    if type(value) ~= 'string' then return fail(errors, path, 'expected a string') end

    return true, value
  end,

  literal = function(t, value, path, errors)
    if vim.tbl_contains(t.values, value) then return true, value end

    return fail(errors, path, 'expected one of: ' .. table.concat(vim.tbl_map(tostring, t.values), ', '))
  end,

  list = function(t, value, path, errors)
    if type(value) ~= 'table' then return fail(errors, path, 'expected a list') end

    local out, ok = {}, true

    for i = 1, #value do
      local item_ok, item = validate(t.item, value[i], path .. '[' .. i .. ']', errors)

      ok = ok and item_ok
      out[i] = item
    end

    return ok, out
  end,

  dict = function(t, value, path, errors)
    if type(value) ~= 'table' then return fail(errors, path, 'expected an object') end

    local out, ok = {}, true

    for key, item in pairs(value) do
      local item_ok, coerced = validate(t.value, item, child(path, key), errors)

      ok = ok and item_ok
      out[key] = coerced
    end

    return ok, out
  end,

  model = function(t, value, path, errors)
    if type(value) ~= 'table' then return fail(errors, path, 'expected an object') end

    local out, ok, known = {}, true, {}

    for _, field in ipairs(t.fields) do
      known[field.name] = true

      local item = value[field.name]

      if item == nil or item == vim.NIL then
        if not field.optional then ok = fail(errors, child(path, field.name), 'required') end
      else
        local item_ok, coerced = validate(field.type, item, child(path, field.name), errors)

        ok = ok and item_ok
        out[field.name] = coerced
      end
    end

    for key in pairs(value) do
      if not known[key] then ok = fail(errors, child(path, key), 'unknown argument') end
    end

    return ok, out
  end,
}

validate = function(t, value, path, errors)
  return VALIDATORS[t.kind](t, value, path, errors)
end

function schema.validate(t, value)
  local errors = {}
  local ok, coerced = validate(t, value, '', errors)

  if ok then return true, coerced end

  return false, errors
end

function schema.format_errors(errors)
  return table.concat(
    vim.tbl_map(function(e)
      return e.path ~= '' and (e.path .. ': ' .. e.message) or e.message
    end, errors),
    '; '
  )
end

local JSON_TYPES = { bool = 'boolean', int = 'integer', float = 'number', str = 'string' }

function schema.json_schema(t)
  local out

  if t.kind == 'any' then
    return {}
  elseif JSON_TYPES[t.kind] then
    out = { type = JSON_TYPES[t.kind] }
  elseif t.kind == 'literal' then
    out = { enum = t.values }
  elseif t.kind == 'list' then
    out = { type = 'array', items = schema.json_schema(t.item) }
  elseif t.kind == 'dict' then
    out = { type = 'object', additionalProperties = schema.json_schema(t.value) }
  elseif t.kind == 'model' then
    local properties, required = {}, {}

    for _, field in ipairs(t.fields) do
      properties[field.name] = schema.json_schema(field.type)

      if not field.optional then required[#required + 1] = field.name end
    end

    out = { type = 'object', properties = properties, required = required, additionalProperties = false }
  end

  out.description = t.description

  return out
end

return schema

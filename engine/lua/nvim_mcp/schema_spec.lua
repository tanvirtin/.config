local schema = require('nvim_mcp.schema')

local eq = assert.are.same

local ARGS = schema.model({
  { name = 'path', type = schema.str({ description = 'File path.' }), optional = true },
  { name = 'line', type = schema.int() },
  { name = 'mode', type = schema.literal({ 'file', 'directory' }), optional = true },
  { name = 'names', type = schema.list(schema.str()), optional = true },
})

local function errors(value)
  local ok, result = schema.validate(ARGS, value)

  eq(false, ok)

  return schema.format_errors(result)
end

describe('nvim_mcp.schema:', function()
  describe('validate', function()
    it('accepts valid arguments and leaves omitted optionals out', function()
      eq({ true, { line = 3, names = { 'a' } } }, { schema.validate(ARGS, { line = 3, names = { 'a' } }) })
    end)

    it('coerces numeric and boolean strings', function()
      local _, value = schema.validate(ARGS, { line = '7' })

      eq(7, value.line)
      eq({ true, true }, { schema.validate(schema.bool(), 'true') })
    end)

    it('reports a missing required field', function()
      eq('line: required', errors({}))
    end)

    it('treats JSON null as missing', function()
      eq({ true, { line = 1 } }, { schema.validate(ARGS, { line = 1, path = vim.NIL }) })
    end)

    it('rejects unknown arguments', function()
      eq('lines: unknown argument', errors({ line = 1, lines = 2 }))
    end)

    it('reports wrong types, literals and list items with their path', function()
      eq('line: expected an integer', errors({ line = 1.5 }))
      eq('mode: expected one of: file, directory', errors({ line = 1, mode = 'pipe' }))
      eq('names[2]: expected a string', errors({ line = 1, names = { 'a', 2 } }))
    end)

    it('collects every error in one pass', function()
      eq('line: required; extra: unknown argument', errors({ extra = true }))
    end)
  end)

  describe('json_schema', function()
    it('describes a model with required fields and no extra properties', function()
      local out = schema.json_schema(ARGS)

      eq('object', out.type)
      eq({ 'line' }, out.required)
      eq(false, out.additionalProperties)
      eq({ type = 'string', description = 'File path.' }, out.properties.path)
      eq({ enum = { 'file', 'directory' } }, out.properties.mode)
      eq({ type = 'array', items = { type = 'string' } }, out.properties.names)
    end)

    it('describes any as an unconstrained schema', function()
      eq({}, schema.json_schema(schema.any()))
      eq({ type = 'object', additionalProperties = {} }, schema.json_schema(schema.dict(schema.any())))
    end)
  end)
end)

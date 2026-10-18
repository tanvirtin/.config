local api = require('nvim_mcp.api')
local schema = require('nvim_mcp.schema')

local eq = assert.are.same

local function json_type(api_type)
  return schema.json_schema(api.schema_type(api_type))
end

local DOCS = [[
*nvim_buf_get_lines()*
    Gets a line-range from the buffer.

    Indexing is zero-based.

*nvim_command()*
    Executes an Ex command.
]]

local FUNCTIONS = {
  {
    name = 'nvim_buf_get_lines',
    method = true,
    parameters = {
      { 'Buffer', 'buffer' },
      { 'Integer', 'start' },
      { 'Integer', 'end' },
      { 'Boolean', 'strict_indexing' },
    },
  },
  {
    name = 'nvim_get_mode',
    method = false,
    parameters = {},
  },
  {
    name = 'nvim_command',
    method = false,
    parameters = { { 'String', 'command' } },
  },
  {
    name = 'vim_helper',
    method = false,
    parameters = {},
  },
}

describe('nvim_mcp.api:', function()
  describe('schema_type', function()
    it('maps scalar api types', function()
      eq({ type = 'integer' }, json_type('Integer'))
      eq({ type = 'string' }, json_type('String'))
      eq({ type = 'boolean' }, json_type('Boolean'))
    end)

    it('maps handles to integers', function()
      eq({ type = 'integer' }, json_type('Buffer'))
      eq({ type = 'integer' }, json_type('Window'))
    end)

    it('maps unknown or untyped values to any', function()
      eq({}, json_type('Object'))
    end)
  end)

  describe('parse_docs', function()
    it('extracts the first paragraph under each tag', function()
      local docs = api.parse_docs(DOCS)

      eq('Gets a line-range from the buffer.', docs.nvim_buf_get_lines)
      eq('Executes an Ex command.', docs.nvim_command)
    end)

    it('reads the paragraph past an unindented signature line', function()
      local text = table.concat({
        '                                    *nvim_buf_get_lines()*',
        'nvim_buf_get_lines({buf}, {start}, {end})',
        '    Gets a line-range from the buffer.',
        '',
      }, '\n')

      eq('Gets a line-range from the buffer.', api.parse_docs(text).nvim_buf_get_lines)
    end)

    it('drops a wrapped signature tail from the summary', function()
      local text = table.concat({
        '*nvim_buf_get_text()*',
        '    {start_row}, {start_col}, {end_row},',
        '    {end_col}, {opts}) Gets a range from the buffer.',
        '',
      }, '\n')

      eq('Gets a range from the buffer.', api.parse_docs(text).nvim_buf_get_text)
    end)

    it('ignores text without a tag', function()
      eq({}, api.parse_docs('just prose\n\nno tags here'))
    end)

    it('caps long summaries', function()
      local long = '*nvim_long()*\n    ' .. string.rep('word ', 100)
      local summary = api.parse_docs(long).nvim_long

      assert.is_true(#summary <= 300)
      assert.is_true(summary:sub(-3) == '...')
    end)
  end)

  describe('risk', function()
    it('marks code-running functions as exec', function()
      eq('exec', api.risk('nvim_command'))
      eq('exec', api.risk('nvim_exec_lua'))
    end)

    it('marks query functions as read', function()
      eq('read', api.risk('nvim_buf_get_lines'))
      eq('read', api.risk('nvim_get_mode'))
      eq('read', api.risk('nvim_buf_line_count'))
    end)

    it('defaults unknown names to write', function()
      eq('write', api.risk('nvim_buf_set_lines'))
    end)
  end)

  describe('entries', function()
    local entries = api.entries(FUNCTIONS, api.parse_docs(DOCS))

    it('skips functions that are not nvim_ prefixed', function()
      eq(3, #entries)
      for _, entry in ipairs(entries) do
        assert.is_true(entry.name:sub(1, 5) == 'nvim_')
      end
    end)

    it('sorts by name', function()
      eq('nvim_buf_get_lines', entries[1].name)
      eq('nvim_command', entries[2].name)
      eq('nvim_get_mode', entries[3].name)
    end)

    it('uses the doc summary when present and the parameter list otherwise', function()
      local by_name = {}

      for _, entry in ipairs(entries) do
        by_name[entry.name] = entry
      end

      eq('Gets a line-range from the buffer.', by_name.nvim_buf_get_lines.summary)
      eq('Neovim API function nvim_get_mode()', by_name.nvim_get_mode.summary)
      eq('rpc', by_name.nvim_get_mode.kind)
    end)

    it('makes the handle parameter optional on method functions only', function()
      local buf = entries[1].params

      eq(true, buf[1].optional)
      eq(false, buf[2].optional)
      eq(false, entries[2].params[1].optional)
    end)

    it('makes container parameters optional', function()
      local fn = api.entries({ { name = 'nvim_x', parameters = { { 'Dict', 'opts' }, { 'Array', 'list' } } } })[1]

      eq(true, fn.params[1].optional)
      eq(true, fn.params[2].optional)
    end)
  end)

  describe('positional_args', function()
    local entry = api.entries(FUNCTIONS, {})[1]

    it('orders named args by parameter position', function()
      local args, err = api.positional_args(entry, { start = 0, ['end'] = -1, strict_indexing = false })

      eq(nil, err)
      eq({ 0, 0, -1, false }, args)
    end)

    it('defaults a missing handle to 0', function()
      local args = api.positional_args(entry, { start = 0, ['end'] = -1, strict_indexing = true })

      eq(0, args[1])
    end)

    it('reports a missing required argument', function()
      local args, err = api.positional_args(entry, { start = 0 })

      eq(nil, args)
      assert.is_truthy(err:find('end: required', 1, true))
    end)

    it('rejects an unknown argument instead of defaulting the handle', function()
      local args, err = api.positional_args(entry, { buf = 3, start = 0, ['end'] = -1, strict_indexing = false })

      eq(nil, args)
      assert.is_truthy(err:find('buf: unknown argument', 1, true))
      assert.is_truthy(err:find('parameters: buffer, start, end, strict_indexing', 1, true))
    end)

    it('rejects a wrongly typed argument and coerces numeric strings', function()
      eq(nil, (api.positional_args(entry, { start = 'x', ['end'] = -1, strict_indexing = false })))
      eq({ 0, 1, -1, false }, api.positional_args(entry, { start = '1', ['end'] = -1, strict_indexing = false }))
    end)

    it('fills omitted containers, sending an empty Dict as a dict', function()
      local fn = api.entries({ { name = 'nvim_x', parameters = { { 'Dict', 'opts' }, { 'Array', 'list' } } } })[1]
      local args = api.positional_args(fn, {})

      eq('{}', vim.json.encode(args[1]))
      eq('[]', vim.json.encode(args[2]))
    end)
  end)
end)

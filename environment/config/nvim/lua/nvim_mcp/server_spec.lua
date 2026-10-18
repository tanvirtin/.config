local server = require('nvim_mcp.server')

local eq = assert.are.same

local FUNCTIONS = {
  {
    name = 'nvim_buf_get_lines',
    method = true,
    parameters = { { 'Buffer', 'buffer' }, { 'Integer', 'start' } },
  },
  { name = 'nvim_get_mode', method = false, parameters = {} },
  { name = 'nvim_set_thing', method = false, parameters = { { 'Dict', 'opts' } } },
  { name = 'nvim_command', method = false, parameters = { { 'String', 'command' } } },
}

local function protocol(call, call_lua)
  return server.new(server.entries(require('nvim_mcp.tools').definitions(), FUNCTIONS, {}), call or function()
    return 'called'
  end, call_lua)
end

local function tools(handler)
  local by_name = {}
  local names = {}

  for _, tool in ipairs(handler:handle({ jsonrpc = '2.0', id = 2, method = 'tools/list' }).result.tools) do
    by_name[tool.name] = tool
    names[#names + 1] = tool.name
  end

  return by_name, names
end

local function call(handler, name, arguments)
  return handler:handle({
    jsonrpc = '2.0',
    id = 5,
    method = 'tools/call',
    params = { name = name, arguments = arguments },
  }).result
end

describe('nvim_mcp.server:', function()
  it('answers initialize with the requested protocol version and instructions', function()
    local reply =
      protocol():handle({ jsonrpc = '2.0', id = 1, method = 'initialize', params = { protocolVersion = '2024-11-05' } })

    eq(1, reply.id)
    eq('2024-11-05', reply.result.protocolVersion)
    eq('nvim-mcp', reply.result.serverInfo.name)
    eq(server.INSTRUCTIONS, reply.result.instructions)
  end)

  it('sends no reply to notifications', function()
    eq(nil, protocol():handle({ jsonrpc = '2.0', method = 'notifications/initialized' }))
  end)

  it('returns method-not-found for unknown methods', function()
    local reply = protocol():handle({ jsonrpc = '2.0', id = 9, method = 'nope' })

    eq(-32601, reply.error.code)
    eq(9, reply.id)
  end)

  describe('tools/list', function()
    it('lists the editor tools first, then every raw API function at every tier', function()
      local by_name, names = tools(protocol())

      eq('editor_state', names[1])
      assert.is_truthy(by_name.buffer_edit)
      assert.is_truthy(by_name.lua)
      assert.is_truthy(by_name.nvim_buf_get_lines)
      assert.is_truthy(by_name.nvim_set_thing)
      assert.is_truthy(by_name.nvim_command)
    end)

    it('gives every tool a typed schema that rejects unknown arguments', function()
      local by_name = tools(protocol())

      eq(false, by_name.buffer_edit.inputSchema.additionalProperties)
      eq({ 'old_string', 'new_string' }, by_name.buffer_edit.inputSchema.required)
      eq('integer', by_name.nvim_buf_get_lines.inputSchema.properties.start.type)
      eq(false, by_name.nvim_buf_get_lines.inputSchema.additionalProperties)
    end)

    it('marks tiers in annotations and _meta', function()
      local by_name = tools(protocol())

      eq({ readOnlyHint = true, openWorldHint = false }, by_name.buffer_read.annotations)
      eq('read', by_name.buffer_read._meta.tier)
      eq(false, by_name.buffer_edit.annotations.destructiveHint)
      eq('write', by_name.buffer_edit._meta.tier)
      eq(true, by_name.buffer_save.annotations.destructiveHint)
      eq(true, by_name.lua.annotations.destructiveHint)
      eq('exec', by_name.nvim_command._meta.tier)
      assert.is_truthy(by_name.nvim_command.description:find('[raw API, exec]', 1, true))
    end)

    it('raises the result size limit for buffer_read', function()
      eq(200000, tools(protocol()).buffer_read._meta['anthropic/maxResultSizeChars'])
    end)

    it('encodes empty schema objects as JSON objects, not arrays', function()
      local text = server.encode(protocol():handle({ jsonrpc = '2.0', id = 2, method = 'tools/list' }))

      assert.is_falsy(text:find('"properties":[]', 1, true))
      assert.is_truthy(text:find('"properties":{}', 1, true))
      assert.is_truthy(text:find('"additionalProperties":{}', 1, true))
    end)
  end)

  describe('tools/call', function()
    it('runs an editor tool in the editor with named arguments', function()
      local seen
      local handler = protocol(nil, function(name, args)
        seen = { name, args }
        return { replacements = 1 }
      end)

      local result = call(handler, 'buffer_edit', { old_string = 'a', new_string = 'b' })

      eq({ 'buffer_edit', { old_string = 'a', new_string = 'b' } }, seen)
      eq(false, result.isError)
      eq('{"replacements":1}', result.content[1].text)
    end)

    it('passes a string result through as text', function()
      local result = call(
        protocol(nil, function()
          return '     1\talpha'
        end),
        'buffer_read',
        {}
      )

      eq('     1\talpha', result.content[1].text)
    end)

    it('reports an editor-side failure as an error result', function()
      local result = call(
        protocol(nil, function()
          error('old_string not found', 0)
        end),
        'buffer_edit',
        { old_string = 'a', new_string = 'b' }
      )

      eq(true, result.isError)
      eq('old_string not found', result.content[1].text)
    end)

    it('calls a raw API function with positional arguments', function()
      local seen
      local handler = protocol(function(name, positional)
        seen = { name = name, positional = positional }
        return { 'alpha' }
      end)

      local result = call(handler, 'nvim_buf_get_lines', { buffer = 3, start = 0 })

      eq({ name = 'nvim_buf_get_lines', positional = { 3, 0 } }, seen)
      eq('["alpha"]', result.content[1].text)
    end)

    it('encodes a nil raw result as null', function()
      eq('null', call(protocol(function() end), 'nvim_command', { command = 'echo 1' }).content[1].text)
    end)

    it('rejects an unknown raw argument instead of defaulting the handle', function()
      local result = call(protocol(), 'nvim_buf_get_lines', { buf = 3, start = 0 })

      eq(true, result.isError)
      assert.is_truthy(result.content[1].text:find('buf: unknown argument', 1, true))
      assert.is_truthy(result.content[1].text:find('(parameters: buffer, start)', 1, true))
    end)

    it('reports a missing raw argument', function()
      local result = call(protocol(), 'nvim_buf_get_lines', {})

      eq(true, result.isError)
      assert.is_truthy(result.content[1].text:find('start: required', 1, true))
    end)

    it('reports an unknown tool', function()
      local result = call(protocol(), 'nope', {})

      eq(true, result.isError)
      eq('unknown tool: nope', result.content[1].text)
    end)

    it('reports a raw call failure as an error result', function()
      local result = call(
        protocol(function()
          error('Invalid buffer id: 999')
        end),
        'nvim_buf_get_lines',
        { buffer = 999, start = 0 }
      )

      eq(true, result.isError)
      assert.is_truthy(result.content[1].text:find('Invalid buffer id', 1, true))
    end)
  end)
end)

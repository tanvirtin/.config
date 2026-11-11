local server = require('nvim_mcp.server')

local eq = assert.are.same

local function protocol(call_editor)
  return server.new(require('nvim_mcp.tools').definitions(), call_editor or function()
    return 'called'
  end)
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
    it('lists the editor tools and none of the raw API', function()
      local by_name, names = tools(protocol())

      eq('editor_state', names[1])
      assert.is_truthy(by_name.buffer_edit)
      assert.is_truthy(by_name.lua)

      for _, name in ipairs(names) do
        assert.is_falsy(name:match('^nvim_'))
      end
    end)

    it('gives every tool a typed schema that rejects unknown arguments', function()
      local by_name = tools(protocol())

      eq(false, by_name.buffer_edit.inputSchema.additionalProperties)
      eq({ 'old_string', 'new_string' }, by_name.buffer_edit.inputSchema.required)
      eq('integer', by_name.buffer_read.inputSchema.properties.start_line.type)
      eq(false, by_name.buffer_read.inputSchema.additionalProperties)
    end)

    it('marks tiers in annotations and _meta', function()
      local by_name = tools(protocol())

      eq({ readOnlyHint = true, openWorldHint = false }, by_name.buffer_read.annotations)
      eq('read', by_name.buffer_read._meta.tier)
      eq(false, by_name.buffer_edit.annotations.destructiveHint)
      eq('write', by_name.buffer_edit._meta.tier)
      eq(true, by_name.buffer_save.annotations.destructiveHint)
      eq(true, by_name.lua.annotations.destructiveHint)
      eq('exec', by_name.lua._meta.tier)
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
      local handler = protocol(function(name, args)
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
        protocol(function()
          return '     1\talpha'
        end),
        'buffer_read',
        {}
      )

      eq('     1\talpha', result.content[1].text)
    end)

    it('reports an editor-side failure as an error result', function()
      local result = call(
        protocol(function()
          error('old_string not found', 0)
        end),
        'buffer_edit',
        { old_string = 'a', new_string = 'b' }
      )

      eq(true, result.isError)
      eq('old_string not found', result.content[1].text)
    end)

    it('leaves editor tool results as text only, so large reads are not duplicated', function()
      local result = call(
        protocol(function()
          return '     1\talpha'
        end),
        'buffer_read',
        {}
      )

      eq(nil, result.structuredContent)
    end)

    it('encodes a nil result as null', function()
      eq('null', call(protocol(function() end), 'ex', { command = 'echo 1' }).content[1].text)
    end)

    it('reports an unknown tool', function()
      local result = call(protocol(), 'nope', {})

      eq(true, result.isError)
      eq('unknown tool: nope', result.content[1].text)
    end)
  end)

  describe('error_text', function()
    it('keeps a tool error\'s reason, without the Lua prefix and stack trace Neovim adds', function()
      eq(
        'invalid arguments for buffer_edit: old_string: required',
        server.error_text(
          'Lua: invalid arguments for buffer_edit: old_string: required\nstack traceback:\n  [C]: in function \'error\''
        )
      )
      eq('plain', server.error_text('plain'))
    end)
  end)
end)

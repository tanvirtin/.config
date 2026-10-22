local api = require('nvim_mcp.api')
local schema = require('nvim_mcp.schema')

local server = {}

local PROTOCOL_VERSION = '2025-06-18'
local SERVER_INFO = { name = 'nvim-mcp', version = '0.2.0' }

local METHOD_NOT_FOUND = -32601
local INVALID_PARAMS = -32602

server.INSTRUCTIONS = table.concat({
  'These tools drive the Neovim editor the user is working in.',
  'Start with editor_state to see the focused file, cursor and open buffers.',
  'Read and edit through buffer_read and buffer_edit rather than the file on disk: buffers can hold unsaved changes, and edits land in the editor as one undo step each.',
  'Editor tools take a path (or bufnr; omit both for the focused buffer) and 1-based, inclusive lines.',
  'Edits stay unsaved; call buffer_save only when the user asks to save.',
  'The nvim_* tools are the raw RPC API: 0-based rows, integer handles, and argument names exactly as their schema lists. Use them for anything the editor tools do not cover.',
  'For anything visual or multi-step, write one Lua script with the lua tool instead of many small calls: fill a quickfix list, open a float or scratch buffer, draw extmarks. Present results in the editor when that helps the user explore.',
}, ' ')

local MAX_RESULT_CHARS = { buffer_read = 200000 }

local function text_result(value, is_error)
  if value == nil then value = vim.NIL end

  local text = type(value) == 'string' and value or vim.json.encode(value)

  return { content = { { type = 'text', text = text } }, isError = is_error == true }
end

function server.error_text(err)
  local text = tostring(err)

  text = text:gsub('\n%s*stack traceback:.*$', '')
  text = text:gsub('^Error executing lua:?%s*', ''):gsub('^Lua:%s*', '')

  return (text:gsub('%s+$', ''))
end

local SCHEMA_KEYS = { properties = true, additionalProperties = true, items = true }

local function fix_objects(node)
  if type(node) ~= 'table' then return node end

  for key, value in pairs(node) do
    if SCHEMA_KEYS[key] and type(value) == 'table' and next(value) == nil then
      node[key] = vim.empty_dict()
    else
      fix_objects(value)
    end
  end

  return node
end

function server.encode(message)
  return vim.json.encode(fix_objects(message))
end

local function annotations(entry)
  if entry.risk == 'read' then return { readOnlyHint = true, openWorldHint = false } end

  local destructive = entry.risk == 'exec'
    or entry.kind == 'rpc'
    or entry.name == 'buffer_save'
    or entry.always_ask == true

  return { readOnlyHint = false, destructiveHint = destructive, openWorldHint = false }
end

function server.tool_definition(entry)
  local description = entry.summary

  if entry.kind == 'rpc' then description = description .. ' [raw API, ' .. entry.risk .. ']' end

  return {
    name = entry.name,
    description = description,
    inputSchema = schema.json_schema(schema.model(entry.params)),
    annotations = annotations(entry),
    _meta = { tier = entry.risk, ['anthropic/maxResultSizeChars'] = MAX_RESULT_CHARS[entry.name] },
  }
end

function server.entries(editor, functions, docs)
  return vim.list_extend(vim.deepcopy(editor), api.entries(functions, docs))
end

function server.new(entries, call_rpc, call_editor)
  local by_name = {}

  for _, entry in ipairs(entries) do
    by_name[entry.name] = entry
  end

  local function call(name, arguments)
    local entry = by_name[name]

    if not entry then return text_result('unknown tool: ' .. tostring(name), true) end

    local ok, value

    if entry.kind == 'editor' then
      ok, value = pcall(call_editor, name, arguments)
    else
      local positional, err = api.positional_args(entry, arguments)

      if not positional then return text_result(err, true) end

      ok, value = pcall(call_rpc, name, positional)
    end

    if not ok then return text_result(server.error_text(value), true) end

    return text_result(value)
  end

  local handlers = {
    initialize = function(params)
      return {
        protocolVersion = (params and params.protocolVersion) or PROTOCOL_VERSION,
        capabilities = { tools = { listChanged = false } },
        serverInfo = SERVER_INFO,
        instructions = server.INSTRUCTIONS,
      }
    end,

    ping = function()
      return vim.empty_dict()
    end,

    ['tools/list'] = function()
      return { tools = vim.tbl_map(server.tool_definition, entries) }
    end,

    ['tools/call'] = function(params)
      params = params or {}

      return call(params.name, params.arguments or {})
    end,
  }

  local self = {}

  function self:handle(message)
    if type(message) ~= 'table' or message.method == nil or message.method:sub(1, 14) == 'notifications/' then
      return nil
    end

    local handler = handlers[message.method]
    local reply = { jsonrpc = '2.0', id = message.id }

    if not handler then
      reply.error = { code = METHOD_NOT_FOUND, message = 'unknown method: ' .. message.method }
      return reply
    end

    local ok, value = pcall(handler, message.params)

    if ok then
      reply.result = value
    else
      reply.error = { code = INVALID_PARAMS, message = tostring(value) }
    end

    return reply
  end

  return self
end

function server.connect(addr)
  local chan = vim.fn.sockconnect('pipe', addr, { rpc = true })

  if chan == 0 then error('cannot connect to editor at ' .. tostring(addr)) end

  local info = vim.rpcrequest(chan, 'nvim_call_function', 'api_info', {})
  local runtime = vim.rpcrequest(chan, 'nvim_eval', '$VIMRUNTIME')
  local docs = {}
  local file = io.open(runtime .. '/doc/api.txt', 'r')

  if file then
    docs = api.parse_docs(file:read('*a'))
    file:close()
  end

  local function call_rpc(name, positional)
    return vim.rpcrequest(chan, name, unpack(positional))
  end

  local editor = vim.rpcrequest(chan, 'nvim_exec_lua', 'return require(\'nvim_mcp.tools\').definitions()', {})
  local caller = vim.env.HARNESS_SESSION or ''

  local function call_editor(name, args)
    if next(args) == nil then args = vim.empty_dict() end

    return vim.rpcrequest(chan, 'nvim_exec_lua', 'return require(\'nvim_mcp.tools\').run(...)', { name, args, caller })
  end

  return server.entries(editor, info.functions, docs), call_rpc, call_editor
end

function server.main(addr)
  if not addr or addr == '' then error('usage: run.lua <editor-socket-address>') end

  local protocol = server.new(server.connect(addr))

  for line in io.lines() do
    local ok, message = pcall(vim.json.decode, line)
    local reply = ok and protocol:handle(message)

    if reply then
      io.stdout:write(server.encode(reply), '\n')
      io.stdout:flush()
    end
  end
end

return server

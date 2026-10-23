local fences = require('core.fences')
local dataclass = require('core.dataclass')

local events = {}

events.KIND = dataclass.enum({
  'message',
  'thought',
  'user',
  'prompt',
  'tool_call',
  'tool_update',
  'plan',
  'title',
  'usage',
  'permission',
  'stop',
  'error',
  'config',
  'mode',
  'commands',
  'subagent',
  'delegation',
})

events.NOTICE = dataclass.enum({ 'queue', 'waiting', 'reset', 'appended', 'external', 'config', 'returned', 'loaded' })

local K = events.KIND

events.TEXT = { [K.user] = true, [K.message] = true, [K.thought] = true }

local STRING = { type = 'string' }
local TABLE = { type = 'table' }

local function schema(fields)
  fields.kind = { type = 'string', required = true }
  return fields
end

local function tool_schema(extra)
  local fields = {
    id = STRING,
    parent = STRING,
    name = STRING,
    category = STRING,
    title = STRING,
    status = STRING,
    input = TABLE,
    locations = TABLE,
    diffs = {
      type = 'table',
      default = function()
        return {}
      end,
    },
  }

  for key, value in pairs(extra or {}) do
    fields[key] = value
  end

  return schema(fields)
end

local text_schema = function(name, extra)
  local fields = { text = { type = 'string', required = true }, parent = STRING, message_id = STRING }

  for key, value in pairs(extra or {}) do
    fields[key] = value
  end

  return dataclass.define(name, schema(fields))
end

events.TYPES = {
  [K.message] = text_schema('Message'),
  [K.thought] = text_schema('Thought'),
  [K.user] = text_schema('User'),
  [K.prompt] = text_schema('Prompt', { steered = { type = 'boolean' } }),
  [K.tool_call] = dataclass.define('ToolCall', tool_schema({ output = STRING })),
  [K.tool_update] = dataclass.define('ToolUpdate', tool_schema({ output = STRING })),
  [K.plan] = dataclass.define('Plan', schema({ entries = { type = 'table', required = true } })),
  [K.title] = dataclass.define('Title', schema({ title = { type = 'string', required = true } })),
  [K.usage] = dataclass.define(
    'Usage',
    schema({ used = { type = 'number' }, size = { type = 'number' }, cost = { type = 'number' } })
  ),
  [K.permission] = dataclass.define(
    'Permission',
    schema({
      tool = { type = 'string', required = true },
      allowed = { type = 'boolean', required = true },
      id = STRING,
      cancelled = { type = 'boolean' },
    })
  ),
  [K.stop] = dataclass.define('Stop', schema({ reason = STRING })),
  [K.error] = dataclass.define('Error', schema({ message = { type = 'string', required = true } })),
  [K.config] = dataclass.define('Config', schema({ options = { type = 'table', required = true } })),
  [K.mode] = dataclass.define('Mode', schema({ id = { type = 'string', required = true } })),
  [K.commands] = dataclass.define('Commands', schema({ commands = { type = 'table', required = true } })),
  [K.subagent] = dataclass.define(
    'Subagent',
    schema({
      child = { type = 'string', required = true },
      title = STRING,
      description = STRING,
      state = STRING,
      stop = STRING,
    })
  ),
  [K.delegation] = dataclass.define('Delegation', schema({ message = STRING })),
}

function events.new(fields)
  local class = events.TYPES[fields.kind]

  if not class then error(string.format('unknown event kind "%s"', tostring(fields.kind)), 2) end
  if class.is(fields) then return fields end

  return class(fields)
end

local function str(value)
  return type(value) == 'string' and value or nil
end

local function num(value)
  return type(value) == 'number' and value or nil
end

local function diffs(content)
  local out = {}

  for _, item in ipairs(type(content) == 'table' and content or {}) do
    if type(item) == 'table' and item.type == 'diff' then
      out[#out + 1] = { path = str(item.path), old = str(item.oldText) or '', new = str(item.newText) or '' }
    end
  end

  return out
end

local function input_diffs(input)
  if type(input) ~= 'table' then return {} end

  local path = str(input.file_path) or str(input.filePath) or str(input.path)
  local old = str(input.old_string) or str(input.oldString)
  local new = str(input.new_string) or str(input.newString)

  if not (path and old and new) then return {} end

  return { { path = path, old = old, new = new } }
end

local function tool_diffs(update)
  local out = diffs(update.content)

  return #out > 0 and out or input_diffs(update.rawInput)
end

local FINISHED = { completed = true, failed = true }

local function unfence(text)
  local body = text:match('^```[%w_-]*\n(.-)\n?```%s*$')

  return body or text
end

local function language_of(resource)
  local mime = str(resource.mimeType)
  local extension = str(resource.uri) and resource.uri:match('%.([%w_]+)$')

  return (mime and mime:match('^text/x%-(.+)$')) or extension or ''
end

local function fenced(text, language)
  local body = vim.split((text:gsub('\n$', '')), '\n', { plain = true })

  return '\n' .. table.concat(fences.wrap(body, language), '\n') .. '\n'
end

function events.block_text(block)
  if type(block) ~= 'table' then return nil end

  if block.type == 'text' or block.type == nil then return str(block.text) end

  if block.type == 'resource_link' then
    local uri = str(block.uri)
    local name = str(block.title) or str(block.name) or uri

    return uri and string.format('[%s](%s)', name, uri) or name
  end

  if block.type == 'resource' and type(block.resource) == 'table' then
    local resource = block.resource

    if str(resource.text) then return fenced(resource.text, language_of(resource)) end

    return string.format('⟨binary resource: %s⟩', str(resource.uri) or 'unnamed')
  end

  if block.type == 'image' then return string.format('⟨image: %s⟩', str(block.mimeType) or 'image') end
  if block.type == 'audio' then return string.format('⟨audio: %s⟩', str(block.mimeType) or 'audio') end
end

local function raw_output(raw)
  if type(raw) == 'string' then return str(raw) end
  if type(raw) == 'table' and next(raw) ~= nil then
    local ok, encoded = pcall(vim.json.encode, raw)
    return ok and encoded or nil
  end
end

local function output(update)
  if not FINISHED[update.status] then return nil end

  local parts = {}

  for _, item in ipairs(type(update.content) == 'table' and update.content or {}) do
    if type(item) == 'table' and item.type == 'content' then
      local text = events.block_text(item.content)
      if text then parts[#parts + 1] = unfence(text) end
    end
  end

  if #parts > 0 then return table.concat(parts, '\n') end

  return raw_output(update.rawOutput)
end

local function locations(update)
  local out = {}

  for _, location in ipairs(type(update.locations) == 'table' and update.locations or {}) do
    if type(location) == 'table' and str(location.path) then
      out[#out + 1] = { path = location.path, line = num(location.line) }
    end
  end

  return #out > 0 and out or nil
end

local function input(update)
  return type(update.rawInput) == 'table' and next(update.rawInput) ~= nil and update.rawInput or nil
end

function events.parent_of(update)
  local meta = type(update) == 'table' and update._meta or nil

  if type(meta) ~= 'table' then return nil end

  for _, vendor in pairs(meta) do
    if type(vendor) == 'table' and str(vendor.parentToolUseId) then return vendor.parentToolUseId end
  end
end

function events.tool_name(call)
  local meta = type(call) == 'table' and call._meta or nil

  if type(meta) ~= 'table' then return nil end

  for _, vendor in pairs(meta) do
    if type(vendor) == 'table' and str(vendor.toolName) then return vendor.toolName end
  end
end

local function text_of(update)
  return events.block_text(update.content)
end

local FROM_UPDATE = {
  agent_message_chunk = function(update)
    local text = text_of(update)
    return text
      and events.new({
        kind = K.message,
        text = text,
        parent = events.parent_of(update),
        message_id = str(update.messageId),
      })
  end,

  agent_thought_chunk = function(update)
    local text = text_of(update)
    return text and events.new({ kind = K.thought, text = text, parent = events.parent_of(update) })
  end,

  subagent_update = function(update)
    local state = type(update.state) == 'table' and update.state or {}

    return str(update.sessionId)
        and events.new({
          kind = K.subagent,
          child = update.sessionId,
          title = str(update.title),
          description = str(update.description),
          state = str(state.state),
          stop = str(state.stopReason),
        })
      or nil
  end,

  session_message = function(update)
    return events.new({ kind = K.delegation, message = str(update.messageId) })
  end,

  user_message_chunk = function(update)
    local text = text_of(update)
    return text and events.new({ kind = K.user, text = text })
  end,

  tool_call = function(update)
    return events.new({
      kind = K.tool_call,
      id = str(update.toolCallId),
      parent = events.parent_of(update),
      name = events.tool_name(update),
      category = str(update.kind),
      title = str(update.title),
      status = str(update.status),
      input = input(update),
      locations = locations(update),
      output = output(update),
      diffs = tool_diffs(update),
    })
  end,

  tool_call_update = function(update)
    return events.new({
      kind = K.tool_update,
      id = str(update.toolCallId),
      parent = events.parent_of(update),
      name = events.tool_name(update),
      category = str(update.kind),
      title = str(update.title),
      status = str(update.status),
      input = input(update),
      locations = locations(update),
      output = output(update),
      diffs = tool_diffs(update),
    })
  end,

  plan = function(update)
    local entries = {}

    for _, entry in ipairs(update.entries or {}) do
      entries[#entries + 1] = { content = str(entry.content) or '', status = str(entry.status) }
    end

    return events.new({ kind = K.plan, entries = entries })
  end,

  session_info_update = function(update)
    return type(update.title) == 'string' and events.new({ kind = K.title, title = update.title }) or nil
  end,

  config_option_update = function(update)
    return type(update.configOptions) == 'table' and events.new({ kind = K.config, options = update.configOptions })
      or nil
  end,

  current_mode_update = function(update)
    return str(update.currentModeId) and events.new({ kind = K.mode, id = update.currentModeId }) or nil
  end,

  available_commands_update = function(update)
    local commands = {}

    for _, command in ipairs(type(update.availableCommands) == 'table' and update.availableCommands or {}) do
      if type(command) == 'table' and str(command.name) then
        local input = type(command.input) == 'table' and command.input or {}
        commands[#commands + 1] =
          { name = command.name, description = str(command.description), hint = str(input.hint) }
      end
    end

    return events.new({ kind = K.commands, commands = commands })
  end,

  usage_update = function(update)
    local cost = type(update.cost) == 'table' and num(update.cost.amount) or nil

    return events.new({ kind = K.usage, used = num(update.used), size = num(update.size), cost = cost })
  end,
}

function events.from_update(update)
  local convert = FROM_UPDATE[update and update.sessionUpdate]

  return convert and convert(update) or nil
end

function events.prompt(text, opts)
  return events.new({ kind = K.prompt, text = text, steered = opts and opts.steered or nil })
end

function events.permission(tool, allowed, opts)
  opts = opts or {}

  return events.new({ kind = K.permission, tool = tool, allowed = allowed, id = opts.id, cancelled = opts.cancelled })
end

function events.stop(reason)
  return events.new({ kind = K.stop, reason = reason })
end

function events.error(message)
  return events.new({ kind = K.error, message = message })
end

function events.append(history, event)
  event = events.new(event)

  local last = history[#history]

  if events.TEXT[event.kind] and last and last.kind == event.kind and last.parent == event.parent then
    last.text = last.text .. event.text
    last.message_id = event.message_id or last.message_id
  else
    history[#history + 1] = vim.deepcopy(event)
  end
end

return events

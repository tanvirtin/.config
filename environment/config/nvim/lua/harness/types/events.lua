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

events.STOP_REASON = dataclass.enum({ 'end_turn', 'max_tokens', 'max_turn_requests', 'refusal', 'cancelled' })

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
  [K.user] = text_schema('User', { selections = TABLE }),
  [K.prompt] = text_schema('Prompt', { steered = { type = 'boolean' }, selections = TABLE }),
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

function events.prompt(text, opts)
  opts = opts or {}

  return events.new({ kind = K.prompt, text = text, steered = opts.steered, selections = opts.selections })
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

    if event.selections then
      last.selections = vim.list_extend(vim.deepcopy(last.selections or {}), event.selections)
    end
  else
    history[#history + 1] = vim.deepcopy(event)
  end
end

return events

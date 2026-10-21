local dataclass = require('core.dataclass')

local Block

local KIND =
  dataclass.enum({ 'title', 'collapsed', 'prompt', 'message', 'thought', 'tool', 'diff', 'plan', 'note', 'stop' })

local STRING, NUMBER, BOOLEAN, TABLE =
  { type = 'string' }, { type = 'number' }, { type = 'boolean' }, { type = 'table' }

Block = dataclass.define('Block', {
  kind = { type = 'string', required = true, enum = KIND },
  lines = { type = 'table', required = true },
  text = STRING,
  first_event = NUMBER,
  last_event = NUMBER,
  live = BOOLEAN,
  first = BOOLEAN,
  steered = BOOLEAN,
  opens_reply = BOOLEAN,
  answered = BOOLEAN,
  error = BOOLEAN,
  id = STRING,
  parent = STRING,
  depth = NUMBER,
  nested = NUMBER,
  path = STRING,
  name = STRING,
  argument = STRING,
  status = STRING,
  category = STRING,
  locations = TABLE,
  output = STRING,
  folds = TABLE,
  added = NUMBER,
  removed = NUMBER,
  started = NUMBER,
  finished = NUMBER,
  reason = STRING,
  duration = NUMBER,
  tools = NUMBER,
  hidden = NUMBER,
  grouped = NUMBER,
  start = NUMBER,
  finish = NUMBER,
  index = NUMBER,
})

Block.KIND = KIND

Block.STATUS = dataclass.enum({ 'pending', 'in_progress', 'completed', 'failed' })

Block.CATEGORY = dataclass.enum({ 'read', 'edit', 'delete', 'move', 'search', 'execute', 'think', 'fetch', 'other' })

function Block.make(kind, lines, fields)
  local all = { kind = kind, lines = lines }

  for key, value in pairs(fields or {}) do
    all[key] = value
  end

  return Block(all)
end

return Block

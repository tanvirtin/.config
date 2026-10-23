local fences = require('core.fences')
local fs = require('core.fs')
local types = require('harness.types.events')

local events = setmetatable({}, { __index = types })

local K = types.KIND

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

function events.selection_of(block)
  local resource = type(block) == 'table' and block.type == 'resource' and block.resource
  local uri = type(resource) == 'table' and str(resource.uri)
  local path, from, to = (uri or ''):match('^file://(.-)#L(%d+)%-?(%d*)$')

  if not path then return nil end

  return string.format('%s:%s', fs.display(path), (to == '' or to == from) and from or (from .. '-' .. to))
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
    local selection = events.selection_of(update.content)

    if selection then return events.new({ kind = K.user, text = '', selections = { selection } }) end

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

return events

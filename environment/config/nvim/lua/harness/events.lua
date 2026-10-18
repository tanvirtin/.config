local events = {}

events.TEXT = { user = true, message = true, thought = true }

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

function events.tool_name(call)
  call = call or {}

  local meta = type(call._meta) == 'table' and call._meta.claudeCode or nil

  return (type(meta) == 'table' and str(meta.toolName)) or nil
end

local function text_of(update)
  return type(update.content) == 'table' and str(update.content.text) or nil
end

local FROM_UPDATE = {
  agent_message_chunk = function(update)
    local text = text_of(update)
    return text and { kind = 'message', text = text }
  end,

  agent_thought_chunk = function(update)
    local text = text_of(update)
    return text and { kind = 'thought', text = text }
  end,

  user_message_chunk = function(update)
    local text = text_of(update)
    return text and { kind = 'user', text = text }
  end,

  tool_call = function(update)
    return {
      kind = 'tool_call',
      id = update.toolCallId,
      name = events.tool_name(update),
      title = str(update.title),
      status = str(update.status),
      input = update.rawInput ~= vim.NIL and update.rawInput or nil,
      diffs = diffs(update.content),
    }
  end,

  tool_call_update = function(update)
    return {
      kind = 'tool_update',
      id = update.toolCallId,
      name = events.tool_name(update),
      title = str(update.title),
      status = str(update.status),
      diffs = diffs(update.content),
    }
  end,

  plan = function(update)
    local entries = {}

    for _, entry in ipairs(update.entries or {}) do
      entries[#entries + 1] = { content = str(entry.content) or '', status = str(entry.status) }
    end

    return { kind = 'plan', entries = entries }
  end,

  session_info_update = function(update)
    return type(update.title) == 'string' and { kind = 'title', title = update.title } or nil
  end,

  usage_update = function(update)
    return { kind = 'usage', used = num(update.used), size = num(update.size) }
  end,
}

function events.from_update(update)
  local convert = FROM_UPDATE[update and update.sessionUpdate]

  return convert and convert(update) or nil
end

function events.prompt(text)
  return { kind = 'prompt', text = text }
end

function events.permission(tool, allowed)
  return { kind = 'permission', tool = tool, allowed = allowed }
end

function events.stop(reason)
  return { kind = 'stop', reason = reason }
end

function events.error(message)
  return { kind = 'error', message = message }
end

function events.append(history, event)
  local last = history[#history]

  if events.TEXT[event.kind] and last and last.kind == event.kind then
    last.text = last.text .. event.text
  else
    history[#history + 1] = vim.deepcopy(event)
  end
end

return events

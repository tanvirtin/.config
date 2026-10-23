local dataclass = require('core.dataclass')
local fences = require('core.fences')
local fs = require('core.fs')
local permission = require('harness.types.permission')
local updates = require('harness.servers.acp.updates')

local translate = {}

local function heading(attachment)
  if attachment.range then
    local source = attachment.source or (attachment.path and fs.display(attachment.path)) or '[No Name]'

    return string.format('Selected lines %d-%d of %s:', attachment.range[1], attachment.range[2], source)
  end

  return (attachment.title or 'Attached') .. ':'
end

function translate.attachment(attachment, prompt_capabilities)
  local range = attachment.range

  if attachment.path and range and (prompt_capabilities or {}).embeddedContext then
    return {
      type = 'resource',
      resource = {
        uri = string.format('file://%s#L%d-%d', attachment.path, range[1], range[2]),
        text = table.concat(attachment.lines, '\n'),
        mimeType = 'text/plain',
      },
    }
  end

  return {
    type = 'text',
    text = heading(attachment) .. '\n' .. table.concat(fences.wrap(attachment.lines, attachment.language), '\n'),
  }
end

function translate.prompt(prompt, prompt_capabilities)
  local blocks = {}

  if prompt.instructions then blocks[#blocks + 1] = { type = 'text', text = prompt.instructions } end
  if prompt.where then blocks[#blocks + 1] = { type = 'text', text = prompt.where } end

  for _, attachment in ipairs(prompt.attachments or {}) do
    blocks[#blocks + 1] = translate.attachment(attachment, prompt_capabilities)
  end

  blocks[#blocks + 1] = { type = 'text', text = prompt.text }

  return blocks
end

function translate.permission_request(params)
  local call = type(params) == 'table' and type(params.toolCall) == 'table' and params.toolCall or {}
  local choices = {}

  for _, option in ipairs(type(params) == 'table' and type(params.options) == 'table' and params.options or {}) do
    if type(option) == 'table' and dataclass.is_member(permission.DECISION, option.kind) then
      local label = type(option.name) == 'string' and option.name ~= '' and option.name or option.kind

      choices[#choices + 1] = { kind = option.kind, label = label }
    end
  end

  return permission.Request({
    tool = updates.tool_name(call) or (type(call.title) == 'string' and call.title) or '',
    id = type(call.toolCallId) == 'string' and call.toolCallId or nil,
    title = type(call.title) == 'string' and call.title or nil,
    input = type(call.rawInput) == 'table' and next(call.rawInput) ~= nil and call.rawInput or nil,
    choices = choices,
  })
end

return translate

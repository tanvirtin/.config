local fs = require('core.fs')
local fences = require('core.fences')
local dataclass = require('core.dataclass')
local permission = require('harness.types.permission')
local updates = require('harness.servers.acp.updates')
local elicitation = require('harness.types.elicitation')

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

      choices[#choices + 1] = permission.Choice({
        kind = option.kind,
        label = label,
        option = type(option.optionId) == 'string' and option.optionId or nil,
      })
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

local FIELD = elicitation.FIELD

local function text_of(value)
  return type(value) == 'string' and value ~= '' and value or nil
end

local function number_of(value)
  return type(value) == 'number' and value or nil
end

local function titled(list)
  local options = {}

  for _, option in ipairs(type(list) == 'table' and list or {}) do
    if type(option) == 'table' and type(option.const) == 'string' then
      local label = text_of(option.title) or option.const
      local description = text_of(option.description)

      options[#options + 1] = elicitation.Option({
        value = option.const,
        label = label,
        description = description ~= label and description or nil,
      })
    end
  end

  return options
end

local function enumerated(values, names)
  local options = {}

  for i, value in ipairs(type(values) == 'table' and values or {}) do
    if type(value) == 'string' then
      local name = type(names) == 'table' and text_of(names[i]) or nil

      options[#options + 1] = elicitation.Option({ value = value, label = name or value })
    end
  end

  return options
end

local function choices_of(schema)
  local options = titled(schema.oneOf)

  if #options == 0 then options = titled(schema.anyOf) end
  if #options == 0 then options = enumerated(schema.enum, schema.enumNames) end

  return options
end

local function spec_of(key, schema, required)
  if type(schema) ~= 'table' then return nil end

  local spec = {
    key = key,
    title = text_of(schema.title),
    description = text_of(schema.description),
    required = required,
  }

  if schema.type == 'string' then
    local options = choices_of(schema)

    spec.kind = #options > 0 and FIELD.choice or FIELD.text
    spec.options = options
    spec.min = number_of(schema.minLength)
    spec.max = number_of(schema.maxLength)
    spec.default = text_of(schema.default)
  elseif schema.type == 'number' or schema.type == 'integer' then
    spec.kind = schema.type == 'integer' and FIELD.integer or FIELD.number
    spec.min = number_of(schema.minimum)
    spec.max = number_of(schema.maximum)
    spec.default = number_of(schema.default)
  elseif schema.type == 'boolean' then
    spec.kind = FIELD.boolean
    if type(schema.default) == 'boolean' then spec.default = schema.default end
  elseif schema.type == 'array' then
    local options = type(schema.items) == 'table' and choices_of(schema.items) or {}

    if #options == 0 then return nil end

    spec.kind = FIELD.multi
    spec.options = options
    spec.min = number_of(schema.minItems)
    spec.max = number_of(schema.maxItems)
    spec.default = type(schema.default) == 'table' and schema.default or nil
  else
    return nil
  end

  return spec
end

local function key_parts(key)
  local out = {}

  for text, digits in key:gmatch('(%D*)(%d*)') do
    if text ~= '' then out[#out + 1] = text end
    if digits ~= '' then out[#out + 1] = tonumber(digits) end
  end

  return out
end

local function natural(a, b)
  local left, right = key_parts(a), key_parts(b)

  for i = 1, math.max(#left, #right) do
    local x, y = left[i], right[i]

    if x == nil then return true end
    if y == nil then return false end
    if type(x) ~= type(y) then return type(x) == 'number' end
    if x ~= y then return x < y end
  end

  return false
end

translate.OTHER_SUFFIX = '_custom'

local function pair_others(specs)
  local by_key = {}

  for _, spec in ipairs(specs) do
    by_key[spec.key] = spec
  end

  for _, spec in ipairs(specs) do
    local base = spec.key:sub(1, -#translate.OTHER_SUFFIX - 1)
    local owner = spec.key:sub(-#translate.OTHER_SUFFIX) == translate.OTHER_SUFFIX and by_key[base] or nil

    if spec.kind == FIELD.text and owner and (owner.kind == FIELD.choice or owner.kind == FIELD.multi) then
      owner.other = spec.key
    end
  end

  return vim.tbl_map(elicitation.Field, specs)
end

function translate.elicitation_request(params)
  if type(params) ~= 'table' then return nil, 'the elicitation has no parameters' end

  local message = type(params.message) == 'string' and params.message or ''
  local tool = text_of(params.toolCallId)

  if params.mode == elicitation.MODE.url then
    if not text_of(params.url) then return nil, 'the elicitation has no url' end

    return elicitation.Request({
      mode = elicitation.MODE.url,
      message = message,
      url = params.url,
      id = text_of(params.elicitationId),
      tool = tool,
    })
  end

  if params.mode ~= elicitation.MODE.form then return nil, 'unsupported elicitation mode: ' .. tostring(params.mode) end

  local schema = type(params.requestedSchema) == 'table' and params.requestedSchema or {}
  local properties = type(schema.properties) == 'table' and schema.properties or {}
  local required = {}

  for _, key in ipairs(type(schema.required) == 'table' and schema.required or {}) do
    required[key] = true
  end

  local keys = vim.tbl_keys(properties)

  table.sort(keys, natural)

  local specs = {}

  for _, key in ipairs(keys) do
    local spec = spec_of(key, properties[key], required[key] == true)

    if spec then
      specs[#specs + 1] = spec
    elseif required[key] then
      return nil, string.format('the elicitation asks for "%s" in a form this client cannot show', key)
    end
  end

  return elicitation.Request({
    mode = elicitation.MODE.form,
    message = message,
    fields = pair_others(specs),
    tool = tool,
  })
end

function translate.elicitation_response(answer)
  if answer.action ~= elicitation.ACTION.accept then return { action = answer.action } end

  local content = {}

  for key, value in pairs(answer.content or {}) do
    if not (type(value) == 'table' and #value == 0) then content[key] = value end
  end

  return { action = answer.action, content = next(content) and content or vim.empty_dict() }
end

return translate

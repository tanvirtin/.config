local dataclass = require('core.dataclass')

local elicitation = {}

elicitation.MODE = dataclass.enum({ 'form', 'url' })

elicitation.FIELD = dataclass.enum({ 'text', 'number', 'integer', 'boolean', 'choice', 'multi' })

elicitation.ACTION = dataclass.enum({ 'accept', 'decline', 'cancel' })

elicitation.CHOICE = dataclass.enum({ 'set', 'toggle', 'done', 'write', 'skip', 'default', 'pick', 'open', 'decline' })

local function list()
  return {}
end

elicitation.Option = dataclass.define('ElicitationOption', {
  value = { type = 'string', required = true },
  label = { type = 'string', required = true },
  description = { type = 'string' },
})

elicitation.Field = dataclass.define('ElicitationField', {
  key = { type = 'string', required = true },
  kind = { type = 'string', required = true, enum = elicitation.FIELD },
  title = { type = 'string' },
  description = { type = 'string' },
  required = { type = 'boolean', default = false },
  default = { type = { 'string', 'number', 'boolean', 'table' } },
  options = { type = 'table', default = list },
  min = { type = 'number' },
  max = { type = 'number' },
  other = { type = 'string' },
})

elicitation.Request = dataclass.define('ElicitationRequest', {
  mode = { type = 'string', required = true, enum = elicitation.MODE },
  message = { type = 'string', required = true },
  fields = { type = 'table', default = list },
  id = { type = 'string' },
  url = { type = 'string' },
  tool = { type = 'string' },
})

elicitation.Answer = dataclass.define('ElicitationAnswer', {
  action = { type = 'string', required = true, enum = elicitation.ACTION },
  content = { type = 'table' },
})

elicitation.Answered = dataclass.define('ElicitationAnswered', {
  label = { type = 'string', required = true },
  value = { type = 'string', required = true },
})

elicitation.Choice = dataclass.define('ElicitationChoice', {
  key = { type = 'string', required = true },
  action = { type = 'string', required = true, enum = elicitation.CHOICE },
  label = { type = 'string', required = true },
  value = { type = { 'string', 'boolean' } },
  description = { type = 'string' },
  target = { type = 'string' },
  checked = { type = 'boolean' },
})

elicitation.View = dataclass.define('ElicitationView', {
  message = { type = 'string', required = true },
  step = { type = 'number', required = true },
  count = { type = 'number', required = true },
  choices = { type = 'table', default = list },
  url = { type = 'string' },
  label = { type = 'string' },
  writing = { type = 'string' },
  error = { type = 'string' },
})

function elicitation.accept(content)
  return elicitation.Answer({ action = elicitation.ACTION.accept, content = content or {} })
end

function elicitation.decline()
  return elicitation.Answer({ action = elicitation.ACTION.decline })
end

function elicitation.cancel()
  return elicitation.Answer({ action = elicitation.ACTION.cancel })
end

function elicitation.answer_of(value)
  if elicitation.Answer.is(value) then return value end
  if type(value) == 'table' and dataclass.is_member(elicitation.ACTION, value.action) then
    return elicitation.Answer({ action = value.action, content = value.content })
  end

  return elicitation.decline()
end

function elicitation.companions(request)
  local out = {}

  for _, field in ipairs(request.fields or {}) do
    if field.other then out[field.other] = true end
  end

  return out
end

function elicitation.label(field)
  local title, description = field.title, field.description

  if title and description and title ~= description then return title .. ': ' .. description end

  return description or title or field.key
end

function elicitation.name(field)
  return field.title or elicitation.label(field)
end

local function shown(field, value)
  if field.kind == elicitation.FIELD.boolean then return value and 'yes' or 'no' end
  if type(value) == 'table' then return table.concat(value, ', ') end

  for _, option in ipairs(field.options) do
    if option.value == value then return option.label end
  end

  return tostring(value)
end

function elicitation.summary(request, answer)
  if answer.action ~= elicitation.ACTION.accept then return {} end

  local out, content = {}, answer.content or {}
  local companion = elicitation.companions(request)

  for _, field in ipairs(request.fields) do
    if not companion[field.key] then
      local parts = {}

      if content[field.key] ~= nil then parts[#parts + 1] = shown(field, content[field.key]) end
      if field.other and content[field.other] ~= nil then parts[#parts + 1] = tostring(content[field.other]) end

      if #parts > 0 then
        out[#out + 1] = elicitation.Answered({ label = elicitation.name(field), value = table.concat(parts, '; ') })
      end
    end
  end

  return out
end

return elicitation

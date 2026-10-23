local dataclass = require('core.dataclass')

local content = {}

content.Attachment = dataclass.define('Attachment', {
  lines = { type = 'table', required = true },
  language = { type = 'string' },
  label = { type = 'string' },
  source = { type = 'string' },
  path = { type = 'string' },
  range = { type = 'table' },
  title = { type = 'string' },
})

content.Context = dataclass.define('Context', {
  where = { type = 'string' },
  attachments = {
    type = 'table',
    default = function()
      return {}
    end,
  },
})

content.Prompt = dataclass.define('Prompt', {
  text = { type = 'string', required = true },
  where = { type = 'string' },
  attachments = {
    type = 'table',
    default = function()
      return {}
    end,
  },
  instructions = { type = 'string' },
})

function content.context(fields)
  return content.Context(fields or {})
end

function content.attach(context, attachment)
  context = context or content.context()
  context.attachments[#context.attachments + 1] = content.Attachment(attachment)

  return context
end

function content.prompt(text, context, instructions)
  return content.Prompt({
    text = text,
    where = context and context.where or nil,
    attachments = context and context.attachments or {},
    instructions = instructions,
  })
end

function content.labels(context)
  local out = {}

  for _, attachment in ipairs(context and context.attachments or {}) do
    if attachment.label then out[#out + 1] = attachment.label end
  end

  return #out > 0 and out or nil
end

return content

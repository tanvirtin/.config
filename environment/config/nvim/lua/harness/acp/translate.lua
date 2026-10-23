local fences = require('core.fences')
local fs = require('core.fs')

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

return translate

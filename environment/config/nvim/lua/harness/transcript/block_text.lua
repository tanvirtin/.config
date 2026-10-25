local fences = require('core.fences')
local Block = require('harness.transcript.Block')
local settings = require('harness.settings.transcript')
local tool_label = require('harness.transcript.tool_label')

local block_text = {}

function block_text.split(text)
  if not text:find('\n', 1, true) then return { text } end

  local lines, from = {}, 1

  while true do
    local at = text:find('\n', from, true)

    if not at then break end

    lines[#lines + 1] = text:sub(from, at - 1)
    from = at + 1
  end

  lines[#lines + 1] = text:sub(from)

  return lines
end

function block_text.quoted(text, prefix)
  local lines = prefix and { prefix } or {}

  for _, line in ipairs(block_text.split(text)) do
    lines[#lines + 1] = line == '' and '>' or '> ' .. line
  end

  return lines
end

function block_text.indented(lines)
  local out = {}

  for i, line in ipairs(lines) do
    out[i] = line == '' and '' or '  ' .. line
  end

  return out
end

function block_text.flatten(items)
  local out = {}

  for _, item in ipairs(items) do
    for _, line in ipairs(block_text.split(item)) do
      out[#out + 1] = line
    end
  end

  return out
end

function block_text.note(label, detail)
  return block_text.flatten({ label .. ': ' .. detail })
end

function block_text.plan(entries)
  local lines, statuses = { 'plan' }, {}

  for i, entry in ipairs(entries) do
    lines[#lines + 1] = string.format('- [%s] %s', entry.status == Block.STATUS.completed and 'x' or ' ', entry.content)
    statuses[i] = entry.status or Block.STATUS.pending
  end

  return lines, statuses
end

function block_text.output(output)
  local lines = block_text.split(output:gsub('%s+$', ''))
  local hidden = #lines - settings:get('output_max')

  if hidden > 0 then
    lines = vim.list_slice(lines, 1, settings:get('output_max'))
    lines[#lines + 1] = string.format('… %d more lines', hidden)
  end

  return lines
end

function block_text.diff(edit, path, text, layout)
  local body = text and edit:text() or edit:patch().lines
  local fence = fences.fence_for(body)
  local label = text and 'diff' or (layout == 'split' and 'split' or 'edit')
  local lines = { fence .. label, '--- ' .. tostring(path) }

  vim.list_extend(lines, body)
  lines[#lines + 1] = fence

  return lines
end

function block_text.tool(name, dir)
  return (tool_label.label({ name = name, input = {} }, name, dir))
end

return block_text

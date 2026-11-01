local compact = require('compact')

local fold_summary = {}

fold_summary.PREVIEW = 48

function fold_summary.preview(lines, max)
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)

    if trimmed ~= '' and not trimmed:find('^```') then return compact.line(trimmed, max or fold_summary.PREVIEW) end
  end
end

function fold_summary.text(count, lines, failed)
  local parts = { count }

  if failed then parts[#parts + 1] = 'failed' end

  local preview = fold_summary.preview(lines)

  if preview then parts[#parts + 1] = '"' .. preview .. '"' end

  return table.concat(parts, ' · ')
end

return fold_summary

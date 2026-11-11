local compact = require('compact')

local fold_summary = {}

fold_summary.PREVIEW = 48

function fold_summary.preview(lines, max, from_end)
  local first, last, step = 1, #lines, 1

  if from_end then
    first, last, step = #lines, 1, -1
  end

  for index = first, last, step do
    local trimmed = vim.trim(lines[index])

    if trimmed ~= '' and not trimmed:find('^```') then return compact.line(trimmed, max or fold_summary.PREVIEW) end
  end
end

function fold_summary.text(count, lines, failed, from_end)
  local parts = { count }

  if failed then parts[#parts + 1] = 'failed' end

  local preview = fold_summary.preview(lines, nil, from_end)

  if preview then parts[#parts + 1] = '"' .. preview .. '"' end

  return table.concat(parts, ' · ')
end

return fold_summary

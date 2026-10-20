local text = {}

local diff = (vim.text and vim.text.diff) or vim.diff

function text.changed_rows(old, new)
  local hunks = diff(table.concat(old, '\n') .. '\n', table.concat(new, '\n') .. '\n', { result_type = 'indices' })
  local rows = {}

  for _, hunk in ipairs(hunks or {}) do
    local start, length = hunk[3], hunk[4]
    local first = math.max(start - 1, 0)
    local last = length > 0 and start + length - 2 or first

    for row = first, math.min(last, #new - 1) do
      rows[#rows + 1] = row
    end
  end

  return rows
end

function text.read_file(path)
  return vim.fn.readfile(path)
end

function text.display_path(path)
  return vim.fn.fnamemodify(path, ':~:.')
end

return text

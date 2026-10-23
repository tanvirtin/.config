local text = {}

local diff = (vim.text and vim.text.diff) or vim.diff

local function joined(lines)
  return #lines == 0 and '' or table.concat(lines, '\n') .. '\n'
end

function text.hunks(old, new)
  return diff(joined(old), joined(new), { result_type = 'indices' }) or {}
end

function text.changed_rows(old, new)
  local rows = {}

  for _, hunk in ipairs(text.hunks(old, new)) do
    local start, length = hunk[3], hunk[4]
    local first = math.max(start - 1, 0)
    local last = length > 0 and start + length - 2 or first

    for row = first, math.min(last, #new - 1) do
      rows[#rows + 1] = row
    end
  end

  return rows
end

function text.plural(n, word, many)
  return string.format('%d %s', n, n == 1 and word or (many or word .. 's'))
end

function text.width(value)
  return vim.fn.strdisplaywidth(value)
end

function text.read_file(path)
  return vim.fn.readfile(path)
end

function text.display_path(path)
  return vim.fn.fnamemodify(path, ':~:.')
end

return text

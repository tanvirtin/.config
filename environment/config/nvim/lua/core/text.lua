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

function text.width_of(chunks)
  local width = 0

  for _, chunk in ipairs(chunks) do
    width = width + text.width(chunk[1])
  end

  return width
end

function text.ago(ms)
  local seconds = math.floor(ms / 1000)

  if seconds < 5 then return 'just now' end
  if seconds < 60 then return seconds .. 's ago' end
  if seconds < 3600 then return math.floor(seconds / 60) .. 'm ago' end
  if seconds < 86400 then return math.floor(seconds / 3600) .. 'h ago' end

  return math.floor(seconds / 86400) .. 'd ago'
end

function text.chars(value)
  return vim.fn.split(value, '\\zs')
end

function text.truncate(value, width)
  if width <= 0 then return '' end
  if text.width(value) <= width then return value end

  for n = vim.fn.strchars(value) - 1, 0, -1 do
    local cut = vim.fn.strcharpart(value, 0, n) .. '─'

    if text.width(cut) <= width then return cut end
  end

  return ''
end

function text.fuzzy(items, query, key)
  return vim.fn.matchfuzzy(items, query, { text_cb = key })
end

function text.read_file(path)
  return vim.fn.readfile(path)
end

function text.display_path(path)
  return vim.fn.fnamemodify(path, ':~:.')
end

return text

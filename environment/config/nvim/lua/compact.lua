local compact = {}

compact.BUDGET = 6000
compact.WIDTH = 160

local CHARS_PER_TOKEN = 4

function compact.path(path)
  if not path or path == '' then return '[No Name]' end

  return vim.fn.fnamemodify(path, ':~:.')
end

function compact.raw(text)
  return vim.trim(tostring(text or ''):gsub('%s+', ' '))
end

function compact.line(text, width)
  width = width or compact.WIDTH

  local line = compact.raw(text)

  if vim.fn.strchars(line) > width then line = vim.fn.strcharpart(line, 0, width - 1) .. '…' end

  return line
end

local function more(hidden, files, next_offset)
  local where = files > 1 and string.format(' in %d files', files) or ''

  return string.format('… %d more%s (offset=%d)', hidden, where, next_offset)
end

function compact.order(items)
  local groups, order = {}, {}

  for _, item in ipairs(items) do
    local key = item.path or '[No Name]'

    if not groups[key] then
      groups[key] = {}
      order[#order + 1] = key
    end

    groups[key][#groups[key] + 1] = item
  end

  local out = {}

  for _, key in ipairs(order) do
    table.sort(groups[key], function(a, b)
      return (a.line or 0) < (b.line or 0)
    end)
    vim.list_extend(out, groups[key])
  end

  return out, groups
end

function compact.locations(items, opts)
  opts = opts or {}

  local budget = opts.budget or compact.BUDGET
  local offset = opts.offset or 0
  local ordered, groups = compact.order(items)
  local total = #ordered
  local out, size, shown = {}, 0, 0
  local current, last_line
  local stopped_at

  local function add(line)
    out[#out + 1] = line
    size = size + #line + 1
  end

  if opts.title then add(string.format('%s (%d)', opts.title, total)) end
  if total == 0 then add(opts.empty or 'no results') end

  for i = offset + 1, total do
    local item = ordered[i]
    local key = item.path or '[No Name]'
    local where = item.line and tostring(item.line) or ''

    if item.col and item.col > 1 then where = where .. ':' .. item.col end

    local text = item.text and compact.line(item.text, opts.width) or ''
    local line = '  ' .. where .. (text ~= '' and (': ' .. text) or '')
    local header = key ~= current and string.format('%s (%d)', compact.path(key), #groups[key]) or nil
    local cost = #line + (header and #header + 1 or 0)

    if size + cost > budget and shown > 0 then
      stopped_at = i
      break
    end

    if header then
      add(header)
      current, last_line = key, nil
    end

    if line ~= last_line then add(line) end

    last_line = line
    shown = shown + 1
  end

  if stopped_at then
    local files = {}

    for i = stopped_at, total do
      files[ordered[i].path or '[No Name]'] = true
    end

    add(more(total - stopped_at + 1, vim.tbl_count(files), stopped_at - 1))
  end

  return table.concat(out, '\n'), { shown = shown, total = total }
end

function compact.rows(rows, columns, opts)
  opts = opts or {}

  local budget = opts.budget or compact.BUDGET
  local out = { table.concat(columns, ' | ') }
  local size = #out[1]

  for i, row in ipairs(rows) do
    local cells = {}

    for j, column in ipairs(columns) do
      local value = row[column]
      cells[j] = value == nil and '' or compact.line(value, opts.width)
    end

    local line = table.concat(cells, ' | ')

    if size + #line > budget then
      out[#out + 1] = string.format('… %d more rows (offset=%d)', #rows - i + 1, i - 1)
      break
    end

    out[#out + 1] = line
    size = size + #line + 1
  end

  return table.concat(out, '\n')
end

function compact.text(text, budget)
  budget = budget or compact.BUDGET

  if #text <= budget then return text end

  local lines = vim.split(text, '\n', { plain = true })
  local head, tail = {}, {}
  local size = 0
  local first, last = 1, #lines

  while first <= last and size < budget * 2 / 3 do
    head[#head + 1] = lines[first]
    size = size + #lines[first] + 1
    first = first + 1
  end

  while last >= first and size < budget do
    table.insert(tail, 1, lines[last])
    size = size + #lines[last] + 1
    last = last - 1
  end

  local omitted = last - first + 1

  if omitted <= 0 then return text:sub(1, budget) .. '…' end

  return table.concat(head, '\n') .. string.format('\n… %d lines omitted …\n', omitted) .. table.concat(tail, '\n')
end

local stats = {}

function compact.reply(caller, raw, text)
  local raw_size = type(raw) == 'string' and #raw or #vim.json.encode(raw == nil and vim.NIL or raw)
  local entry = stats[caller or ''] or { calls = 0, raw = 0, compact = 0 }

  entry.calls = entry.calls + 1
  entry.raw = entry.raw + raw_size
  entry.compact = entry.compact + #text
  stats[caller or ''] = entry

  return text
end

function compact.stats(caller)
  local calls, raw, out = 0, 0, 0

  for key, entry in pairs(stats) do
    if caller == nil or key == caller then
      calls = calls + entry.calls
      raw = raw + entry.raw
      out = out + entry.compact
    end
  end

  return {
    calls = calls,
    raw_tokens = math.ceil(raw / CHARS_PER_TOKEN),
    tokens = math.ceil(out / CHARS_PER_TOKEN),
    saved_tokens = math.max(0, math.ceil((raw - out) / CHARS_PER_TOKEN)),
  }
end

function compact.reset_stats()
  stats = {}
end

return compact

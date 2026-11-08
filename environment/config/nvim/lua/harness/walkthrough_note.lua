local text = require('core.text')

local walkthrough_note = {}

walkthrough_note.MAX_WIDTH = 100
walkthrough_note.HL = {
  surface = 'UiSurface',
  border = { 'UiSurface', 'UiMuted' },
  title = { 'UiSurface', 'UiTitle' },
  code = { 'UiSurface', 'UiMarkdownCode' },
  strong = { 'UiSurface', 'UiAccent' },
}

local function width(value)
  return text.width(value)
end

local function spans(line)
  local out, at = {}, 1

  while at <= #line do
    local code_from, code_to = line:find('`[^`]+`', at)
    local bold_from, bold_to = line:find('%*%*[^*]+%*%*', at)
    local from, to, kind, inner

    if code_from and (not bold_from or code_from < bold_from) then
      from, to, kind, inner = code_from, code_to, 'code', line:sub(code_from + 1, code_to - 1)
    elseif bold_from then
      from, to, kind, inner = bold_from, bold_to, 'strong', line:sub(bold_from + 2, bold_to - 2)
    end

    if not from then
      out[#out + 1] = { line:sub(at), 'surface' }
      break
    end

    if from > at then out[#out + 1] = { line:sub(at, from - 1), 'surface' } end

    out[#out + 1] = { inner, kind }
    at = to + 1
  end

  return out
end

local function words(line)
  local out, spaced = {}, true

  for _, span in ipairs(spans(line)) do
    local value, kind = span[1], span[2]

    if kind == 'code' then
      out[#out + 1] = { value, kind, glued = not spaced }
      spaced = false
    else
      if value:match('^%s') then spaced = true end

      for word in value:gmatch('%S+') do
        out[#out + 1] = { word, kind, glued = not spaced }
        spaced = true
      end

      spaced = value:match('%s$') ~= nil or (spaced and not value:match('%S'))
    end
  end

  return out
end

local function wrap(line, size, lead)
  local rows, row, used = {}, {}, 0

  for _, word in ipairs(words(line)) do
    local gap = (used > 0 and not word.glued) and 1 or 0
    local need = width(word[1]) + gap

    if used > 0 and used + need > size then
      rows[#rows + 1] = row
      row, used, gap = {}, 0, 0
    end

    if gap > 0 then row[#row + 1] = { ' ', 'surface' } end

    row[#row + 1] = { word[1], word[2] }
    used = used + width(word[1]) + gap
  end

  rows[#rows + 1] = row

  for index, each in ipairs(rows) do
    table.insert(each, 1, { index == 1 and lead or string.rep(' ', width(lead)), 'surface' })
  end

  return rows
end

local function chunks(row, size)
  local out, used = {}, 0

  for _, part in ipairs(row) do
    out[#out + 1] = { part[1], walkthrough_note.HL[part[2]] }
    used = used + width(part[1])
  end

  out[#out + 1] = { string.rep(' ', math.max(size - used, 0)), walkthrough_note.HL.surface }

  return out
end

function walkthrough_note.render(lines, opts)
  opts = opts or {}

  local size = math.max(math.min(opts.width or walkthrough_note.MAX_WIDTH, walkthrough_note.MAX_WIDTH) - 2, 10)
  local bar = { '│ ', walkthrough_note.HL.border }
  local out = {}
  local fenced = false

  local function add(row)
    local line = { bar }

    vim.list_extend(line, chunks(row, size))
    out[#out + 1] = line
  end

  local title = opts.title or ''

  out[#out + 1] = {
    { '╭─ ', walkthrough_note.HL.border },
    { title, walkthrough_note.HL.title },
    { ' ' .. string.rep('─', math.max(size - width(title) - 2, 0)), walkthrough_note.HL.border },
  }

  for _, line in ipairs(lines) do
    if line:match('^%s*```') then
      fenced = not fenced
    elseif fenced then
      add({ { line, 'code' } })
    elseif line:match('^%s*$') then
      add({})
    elseif line:match('^%s*%-%-%-+%s*$') then
      out[#out + 1] = { bar, { string.rep('─', size), walkthrough_note.HL.border } }
    elseif line:match('^#+%s') then
      add({ { line:gsub('^#+%s+', ''), 'strong' } })
    else
      local indent, rest = line:match('^(%s*)[-*] (.*)$')

      for _, row in ipairs(rest and wrap(rest, size - #indent - 2, indent .. '• ') or wrap(line, size, '')) do
        add(row)
      end
    end
  end

  out[#out + 1] = {
    { '╰─ ', walkthrough_note.HL.border },
    { opts.footer or '', walkthrough_note.HL.border },
  }

  return out
end

return walkthrough_note

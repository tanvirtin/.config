local MarkSpec = require('ui.MarkSpec')
local text = require('core.text')

local content_table = {}

local function parse(line, delimiter)
  local cells, cell, quoted, i = {}, {}, false, 1

  while i <= #line do
    local char = line:sub(i, i)

    if quoted then
      if char == '"' then
        if line:sub(i + 1, i + 1) == '"' then
          cell[#cell + 1] = '"'
          i = i + 2
        else
          quoted = false
          i = i + 1
        end
      else
        cell[#cell + 1] = char
        i = i + 1
      end
    elseif char == '"' then
      quoted = true
      i = i + 1
    elseif char == delimiter then
      cells[#cells + 1] = table.concat(cell)
      cell = {}
      i = i + 1
    else
      cell[#cell + 1] = char
      i = i + 1
    end
  end

  cells[#cells + 1] = table.concat(cell)

  return cells
end

function content_table.render(block, spec, ctx)
  local lines = block and block.lines

  if not lines then return {} end

  local first = spec.first or 1
  local last = spec.last or (#lines - (spec.trim or 0))
  local delimiter = block.lang == 'tsv' and '\t' or ','
  local rows, widths = {}, {}

  for i = first, last do
    local line = lines[i]

    if line and line ~= '' and not line:match('^…%s+%d+ more lines$') then
      local cells = parse(line, delimiter)

      rows[#rows + 1] = { index = i, cells = cells }

      for c, cell in ipairs(cells) do
        widths[c] = math.max(widths[c] or 0, text.width(cell))
      end
    end
  end

  if #rows == 0 then return {} end

  local out = {}
  local start = block.start or 0

  for r, row in ipairs(rows) do
    local parts = {}

    for c, cell in ipairs(row.cells) do
      parts[#parts + 1] = cell .. string.rep(' ', math.max(widths[c] - text.width(cell), 0))
    end

    local formatted = table.concat(parts, ' │ ')

    if ctx and ctx.width and text.width(formatted) > ctx.width then formatted = text.truncate(formatted, ctx.width) end

    local line = lines[row.index] or ''

    MarkSpec.add(out, start + row.index - 1, 0, { end_col = #line, conceal = '' })
    MarkSpec.add(out, start + row.index - 1, 0, {
      virt_text = { { formatted, r == 1 and 'UiToolName' or 'UiToolOutput' } },
      virt_text_pos = 'overlay',
    })
  end

  return out
end

return content_table

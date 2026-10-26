local MarkSpec = require('ui.MarkSpec')
local text = require('core.text')
local content = require('harness.transcript.content')
local hit_test = require('harness.ui.hit_test')
local content_settings = require('harness.settings.content')

local content_table = {}

local function parse(line, delimiter)
  local cells, ranges, cell, quoted, i, start = {}, {}, {}, false, 1, 0

  local function push(finish)
    cells[#cells + 1] = table.concat(cell)
    ranges[#ranges + 1] = { start, finish }
    cell = {}
  end

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
      push(i - 1)
      start = i
      i = i + 1
    else
      cell[#cell + 1] = char
      i = i + 1
    end
  end

  push(#line)

  return cells, ranges
end

function content_table.render(block, spec, ctx)
  local lines = block and block.lines

  if not lines then return {} end

  local first = spec.first or 1
  local last = spec.last or (#lines - (spec.trim or 0))
  local delimiter = block.lang == 'tsv' and '\t' or ','
  local config = content_settings:get('csv') or {}
  local separator = config.separator or ' │ '
  local max_columns = config.max_columns or math.huge
  local header_group = config.header or 'UiToolName'
  local cell_group = config.cell

  if not cell_group or cell_group == 'auto' then
    cell_group = block.category == 'execute' and 'UiTerminal' or 'UiToolOutput'
  end
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
      if c > max_columns then break end

      parts[#parts + 1] = cell .. string.rep(' ', math.max(widths[c] - text.width(cell), 0))
    end

    local formatted = table.concat(parts, separator)

    if ctx and ctx.width and text.width(formatted) > ctx.width then formatted = text.truncate(formatted, ctx.width) end

    local line = lines[row.index] or ''

    MarkSpec.add(out, start + row.index - 1, 0, { end_col = #line, conceal = '' })
    MarkSpec.add(out, start + row.index - 1, 0, {
      virt_text = { { formatted, r == 1 and header_group or cell_group } },
      virt_text_pos = 'overlay',
    })
  end

  return out
end

hit_test.bind('csv', function(block, row, col)
  local spec = content.option(block, 'table')

  if not spec then return nil end

  local lines = block.lines

  if not lines then return nil end

  local first = spec.first or 1
  local last = spec.last or (#lines - (spec.trim or 0))
  local index = row - (block.start or 0) + 1

  if index < first or index > last then return nil end

  local line = lines[index]

  if not line or line == '' or line:match('^…%s+%d+ more lines$') then return nil end

  local delimiter = block.lang == 'tsv' and '\t' or ','
  local cells, ranges = parse(line, delimiter)

  for c, range in ipairs(ranges) do
    if col >= range[1] and col < range[2] then return { text = cells[c], kind = 'cell' } end
  end
end)

return content_table

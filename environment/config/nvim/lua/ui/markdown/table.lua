local table_layout = {}

table_layout.ALIGN = require('core.dataclass').enum({ 'left', 'center', 'right' })

table_layout.BORDER = {
  top = { '┌', '┬', '┐' },
  middle = { '├', '┼', '┤' },
  bottom = { '└', '┴', '┘' },
  vertical = '│',
  horizontal = '─',
}

table_layout.HL = { border = 'UiMuted', header = 'UiMarkdownTableHeader', cell = 'UiMarkdownTableCell' }

local function width(text)
  return vim.fn.strdisplaywidth(text)
end

function table_layout.widths(rows)
  local widths = {}

  for _, row in ipairs(rows) do
    for i, cell in ipairs(row) do
      widths[i] = math.max(widths[i] or 1, width(cell))
    end
  end

  return widths
end

local function pad(text, size, align)
  local gap = size - width(text)

  if align == table_layout.ALIGN.right then return string.rep(' ', gap) .. text end

  if align == table_layout.ALIGN.center then
    local left = math.floor(gap / 2)
    return string.rep(' ', left) .. text .. string.rep(' ', gap - left)
  end

  return text .. string.rep(' ', gap)
end

local function rule(widths, parts)
  local segments = {}

  for i, size in ipairs(widths) do
    segments[i] = string.rep(table_layout.BORDER.horizontal, size + 2)
  end

  return { { parts[1] .. table.concat(segments, parts[2]) .. parts[3], table_layout.HL.border } }
end

local function row_chunks(cells, widths, aligns, hl)
  local chunks = { { table_layout.BORDER.vertical, table_layout.HL.border } }

  for i, size in ipairs(widths) do
    chunks[#chunks + 1] = { ' ' .. pad(cells[i] or '', size, aligns[i]) .. ' ', hl }
    chunks[#chunks + 1] = { table_layout.BORDER.vertical, table_layout.HL.border }
  end

  return chunks
end

function table_layout.lines(header, rows, aligns)
  local all = { header }

  vim.list_extend(all, rows)

  local widths = table_layout.widths(all)
  local lines = { rule(widths, table_layout.BORDER.top), row_chunks(header, widths, aligns, table_layout.HL.header) }

  if #rows > 0 then lines[#lines + 1] = rule(widths, table_layout.BORDER.middle) end

  for _, row in ipairs(rows) do
    lines[#lines + 1] = row_chunks(row, widths, aligns, table_layout.HL.cell)
  end

  lines[#lines + 1] = rule(widths, table_layout.BORDER.bottom)

  return lines
end

return table_layout

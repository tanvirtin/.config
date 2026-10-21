local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')

local LINE_HL = { GitSignsAddLn = true, GitSignsDeleteLn = true }
local NUMBERED = { context = true, add = true, remove = true }

local function path_row(out, block)
  local row = block.start + 1

  if block.attached then return MarkSpec.add(out, row, 0, { conceal_lines = '' }) end

  MarkSpec.add(out, row, 0, { end_col = 4, conceal = '' })
  MarkSpec.add(out, row, 0, { virt_text = { { theme.PATH_ICON, 'UiPath' } }, virt_text_pos = 'inline' })
  MarkSpec.add(out, row, 4, { end_col = #block.lines[2], hl_group = 'UiPath' })
end

local function rows(out, block, first)
  for i, entry in ipairs(block.patch.rows) do
    local row = first + i - 1

    MarkSpec.add(out, row, 0, {
      virt_text = { { theme.GUTTER, 'UiMuted' } },
      virt_text_pos = 'inline',
      priority = theme.GUTTER_PRIORITY + 1,
    })

    if entry.kind == 'hunk' then
      MarkSpec.add(out, row, 0, { end_col = #block.lines[i + 2], conceal = '' })
      MarkSpec.add(out, row, 0, { virt_text = { { theme.HUNK, 'UiMuted' } }, virt_text_pos = 'inline' })
    elseif NUMBERED[entry.kind] and entry.number then
      local number = block.whole and entry.number.text or string.rep(' ', #entry.number.text)

      MarkSpec.add(out, row, 0, { virt_text = { { number, entry.number.hl } }, virt_text_pos = 'inline' })
    end
  end
end

local WORD = { GitWordAdd = true, GitWordDelete = true }

local function words(out, block, first, by_row)
  for index, ranges in pairs(by_row) do
    table.sort(ranges, function(x, y)
      return x.col_start < y.col_start
    end)

    local line = block.lines[index + 3] or ''
    local texts, col = {}, ranges[1].col_start

    for _, range in ipairs(ranges) do
      if range.col_start > col then texts[#texts + 1] = { line:sub(col + 1, range.col_start) } end

      texts[#texts + 1] = { line:sub(range.col_start + 1, range.col_end), range.hl_group }
      col = range.col_end
    end

    MarkSpec.add(out, first + index, ranges[1].col_start, {
      virt_text = texts,
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
      priority = MarkSpec.PRIORITY + 100,
    })
  end
end

local function highlights(out, block, first)
  local patch_rows = block.patch.rows
  local by_row = {}

  for _, hl in ipairs(block.patch.highlights) do
    local entry = patch_rows[hl.row + 1]
    local row = first + hl.row

    if entry and entry.kind ~= 'hunk' then
      if hl.line then
        if LINE_HL[hl.hl_group] then MarkSpec.add(out, row, 0, { line_hl_group = hl.hl_group }) end
      elseif WORD[hl.hl_group] then
        by_row[hl.row] = by_row[hl.row] or {}
        table.insert(by_row[hl.row], hl)
      elseif hl.col_end > hl.col_start then
        MarkSpec.add(out, row, hl.col_start, {
          end_col = hl.col_end,
          hl_group = hl.hl_group,
          priority = theme.SYNTAX_PRIORITY,
        })
      end
    end
  end

  words(out, block, first, by_row)
end

return function(block)
  local out = {}

  path_row(out, block)

  if block.patch then
    local first = block.start + 2

    rows(out, block, first)
    highlights(out, block, first)
  end

  return out
end

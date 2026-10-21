local DiffLineCalculator = require('harness.transcript.calculators.DiffLineCalculator')
local MarkSpec = require('ui.MarkSpec')
local fs = require('core.fs')
local theme = require('harness.transcript.theme')

local DIFF_HL = { ['+'] = 'UiDiffAdd', ['-'] = 'UiDiffDelete' }
local MARK_HL = { ['+'] = 'UiAdded', ['-'] = 'UiRemoved' }

local function syntax(out, block, ctx, sides, filetype)
  local seen = {}

  for _, side in pairs(sides) do
    for _, highlight in ipairs(ctx.syntax:annotate(side.lines, filetype)) do
      local row = side.rows[highlight.row + 1]
      local key = row and string.format('%d:%d:%s', row, highlight.col_start, highlight.hl_group)

      if row and not seen[key] then
        seen[key] = true

        local text = block.lines[row - block.start + 1]
        local end_col = highlight.col_end == -1 and #text or highlight.col_end + 1

        MarkSpec.add(out, row, highlight.col_start + 1, {
          end_col = end_col,
          hl_group = highlight.hl_group,
          priority = theme.SYNTAX_PRIORITY,
        })
      end
    end
  end
end

return function(block, ctx)
  local out = {}
  local path = block.lines[2]:sub(5)

  MarkSpec.add(out, block.start + 1, 0, { end_col = 4, conceal = '' })
  MarkSpec.add(out, block.start + 1, 0, { virt_text = { { theme.PATH_ICON, 'UiPath' } }, virt_text_pos = 'inline' })
  MarkSpec.add(out, block.start + 1, 4, { end_col = #block.lines[2], hl_group = 'UiPath' })

  local sides = { new = { lines = {}, rows = {} }, old = { lines = {}, rows = {} } }
  local shift = ctx.diff_offset and ctx.diff_offset(block)

  for offset, entry in pairs(DiffLineCalculator.numbers(block.lines)) do
    local row = block.start + offset - 1
    local line = block.lines[offset]

    if entry.mark == '@' then
      MarkSpec.add(out, row, 0, { end_col = #line, conceal = '' })
      MarkSpec.add(out, row, 0, { virt_text = { { theme.HUNK, 'UiMuted' } }, virt_text_pos = 'inline' })
    else
      MarkSpec.add(out, row, 0, {
        virt_text = { { shift and string.format('%4d ', entry.number + shift) or '  ', 'UiDiffLineNr' } },
        virt_text_pos = 'inline',
        line_hl_group = DIFF_HL[entry.mark],
      })

      if MARK_HL[entry.mark] then MarkSpec.add(out, row, 0, { end_col = 1, hl_group = MARK_HL[entry.mark] }) end

      local targets = entry.mark == '+' and { sides.new }
        or entry.mark == '-' and { sides.old }
        or { sides.new, sides.old }

      for _, target in ipairs(targets) do
        target.lines[#target.lines + 1] = line:sub(2)
        target.rows[#target.rows + 1] = row
      end
    end
  end

  local filetype = ctx.syntax and fs.detect_filetype(path) or ''

  if filetype ~= '' then syntax(out, block, ctx, sides, filetype) end

  return out
end

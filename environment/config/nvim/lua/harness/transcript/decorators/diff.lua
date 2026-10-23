local MarkSpec = require('ui.MarkSpec')
local Block = require('harness.transcript.Block')
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
      MarkSpec.add(out, row, 0, { end_col = #block.lines[i + Block.DIFF_HEADER], conceal = '' })
      MarkSpec.add(out, row, 0, { virt_text = { { theme.HUNK, 'UiMuted' } }, virt_text_pos = 'inline' })
    elseif NUMBERED[entry.kind] and entry.number then
      local number = block.whole and entry.number.text or string.rep(' ', #entry.number.text)

      MarkSpec.add(out, row, 0, { virt_text = { { number, entry.number.hl } }, virt_text_pos = 'inline' })
    end
  end
end

local function highlight(out, block, first, hl)
  local entry = block.patch.rows[hl.row + 1]
  local row = first + hl.row

  if not entry or entry.kind == 'hunk' then return end

  if hl.line then
    if LINE_HL[hl.hl_group] then MarkSpec.add(out, row, 0, { line_hl_group = hl.hl_group }) end
  elseif hl.col_end > hl.col_start then
    MarkSpec.add(out, row, hl.col_start, {
      end_col = hl.col_end,
      hl_group = hl.hl_group,
      priority = theme.SYNTAX_PRIORITY,
    })
  end
end

local function highlights(out, block, first)
  local patch = block.patch

  for _, hl in ipairs(patch.highlights or {}) do
    highlight(out, block, first, hl)
  end

  for _, hl in ipairs(patch.syntax and patch.syntax() or {}) do
    highlight(out, block, first, hl)
  end
end

local function words(out, block, first)
  for _, word in ipairs(block.patch.words or {}) do
    MarkSpec.add(out, first + word.row, word.col, {
      virt_text = word.texts,
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
      priority = MarkSpec.PRIORITY + 100,
    })
  end
end

return function(block)
  local out = {}

  path_row(out, block)

  if block.patch then
    local first = block.start + Block.DIFF_HEADER

    rows(out, block, first)
    highlights(out, block, first)
    words(out, block, first)
  end

  return out
end

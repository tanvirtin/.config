local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')

return function(block)
  local out = {}

  for row = block.start, block.finish - 2 do
    local line = block.lines[row - block.start + 1] or ''

    MarkSpec.add(out, row, 0, {
      end_col = math.min(1, #line),
      virt_text = { { row == block.start and theme.PROMPT_ICON or ' ', 'UiPromptBar' } },
      virt_text_pos = 'overlay',
    })

    local selection = block.selections and row >= block.start + #block.lines - block.selections

    if #line > 2 then
      MarkSpec.add(out, row, 2, { end_col = #line, hl_group = selection and 'UiPath' or 'UiPromptText' })
    end
  end

  if block.steered then
    MarkSpec.add(out, block.start, 0, { virt_text = { { '  steered', 'UiMuted' } }, virt_text_pos = 'eol' })
  end

  return out
end

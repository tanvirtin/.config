local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')

return function(block)
  local out = {}

  if not block.label then return out end

  local failed = theme.TOOL_ICONS.failed

  for index, line in ipairs(block.lines) do
    local row = block.start + index - 1

    MarkSpec.add(out, row, 0, {
      virt_text = { { index == 1 and failed[1] or '  ', failed[2] } },
      virt_text_pos = 'inline',
    })

    if index == 1 then
      MarkSpec.add(out, row, 0, { end_col = #block.label + 1, hl_group = 'UiError' })
      MarkSpec.add(
        out,
        row,
        #block.label + 1,
        { end_col = #line, hl_group = block.label == 'error' and 'UiError' or 'UiMuted' }
      )
    elseif block.label == 'error' then
      MarkSpec.add(out, row, 0, { end_col = #line, hl_group = 'UiError' })
    end
  end

  return out
end

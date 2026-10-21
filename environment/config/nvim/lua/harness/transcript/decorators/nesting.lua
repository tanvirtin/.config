local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')

return function(block)
  local out = {}

  if block.depth then
    for row = block.start, block.finish - 1 do
      MarkSpec.add(out, row, 0, {
        virt_text = { { theme.GUTTER, 'UiMuted' } },
        virt_text_pos = 'inline',
        priority = theme.GUTTER_PRIORITY,
      })
    end
  end

  return out
end

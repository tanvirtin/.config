local MarkSpec = require('harness.transcript.MarkSpec')
local theme = require('harness.transcript.theme')

return function(block, ctx)
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

  if block.opens_reply then
    MarkSpec.add(out, block.start, 0, {
      virt_lines = { { { ' ' .. theme.AGENT_ICON .. (ctx.agent or 'Agent'), 'UiSpeakerAgent' } } },
      virt_lines_above = true,
    })
  end

  return out
end

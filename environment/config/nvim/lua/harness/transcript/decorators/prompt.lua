local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')

return function(block, ctx)
  local out = {}
  local header = {
    { { ' ' .. theme.USER_ICON .. 'You', 'UiSpeakerUser' }, block.steered and { ' · steered', 'UiMuted' } or nil },
  }

  if not block.first and not block.steered then
    table.insert(header, 1, { { string.rep('─', theme.SEPARATOR_WIDTH), 'UiTurnSeparator' } })
  end

  MarkSpec.add(out, block.start, 0, { virt_lines = header, virt_lines_above = true })

  for row = block.start, block.finish - 2 do
    MarkSpec.add(out, row, 0, {
      end_col = 1,
      virt_text = { { '▌', 'UiPromptBar' } },
      virt_text_pos = 'overlay',
      line_hl_group = 'UiPrompt',
    })
  end

  if block.answered then
    MarkSpec.add(out, block.finish - 1, 0, {
      virt_lines = { { { ' ' .. theme.AGENT_ICON .. (ctx and ctx.agent or 'Agent'), 'UiSpeakerAgent' } } },
    })
  end

  return out
end

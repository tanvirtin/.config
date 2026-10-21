local BlockBuilder = require('harness.transcript.BlockBuilder')
local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')

return function(block)
  local out = {}
  local done = block.reason == 'end_turn'
  local parts = {}
  local duration = theme.duration(block.duration)

  if not done then parts[1] = (BlockBuilder.STOP_REASONS[block.reason] or tostring(block.reason)):lower() end
  if duration then parts[#parts + 1] = duration end
  if block.tools and block.tools > 0 then parts[#parts + 1] = theme.plural(block.tools, 'tool') end
  if #parts == 0 then parts[1] = 'done' end

  MarkSpec.add(out, block.start, 0, { end_col = #block.lines[1], conceal = '' })
  MarkSpec.add(out, block.start, 0, {
    virt_text = { { string.rep(theme.RULE, theme.RULE_WIDTH), 'UiTurnSeparator' } },
    virt_text_pos = 'overlay',
    priority = theme.GUTTER_PRIORITY,
  })
  MarkSpec.add(out, block.start, 0, {
    virt_text = {
      { ' ' .. table.concat(parts, ' · ') .. ' ', done and 'UiMuted' or 'UiWarn' },
      { string.rep(theme.RULE, 2), 'UiTurnSeparator' },
    },
    virt_text_pos = 'right_align',
  })

  return out
end

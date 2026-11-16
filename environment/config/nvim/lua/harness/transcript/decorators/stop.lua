local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')
local BlockBuilder = require('harness.transcript.BlockBuilder')

local REASON_HL = { end_turn = 'UiMuted', error = 'UiError' }

return function(block, ctx)
  local out = {}
  local done = block.reason == 'end_turn'
  local parts = {}
  local duration = theme.duration(block.duration)

  if not done then parts[1] = BlockBuilder.STOP_REASONS[block.reason] or tostring(block.reason) end
  if duration then parts[#parts + 1] = duration end
  if block.tools and block.tools > 0 then parts[#parts + 1] = theme.plural(block.tools, 'tool') end
  if #parts == 0 then parts[1] = 'done' end

  MarkSpec.add(out, block.start, 0, { end_col = #block.lines[1], conceal = '' })
  local overlay, pixels = theme.rule(ctx, theme.RULE, 'UiTurnSeparator', 'solid')

  MarkSpec.add(out, block.start, 0, {
    virt_text = overlay,
    virt_text_pos = 'overlay',
    priority = theme.GUTTER_PRIORITY,
  })
  local summary = { { ' ' .. table.concat(parts, ' · '), REASON_HL[block.reason] or 'UiWarn' } }

  if block.files then
    vim.list_extend(summary, {
      { ' · ', 'UiMuted' },
      { '+' .. (block.added or 0), 'UiAdded' },
      { ' ' },
      { '−' .. (block.removed or 0), 'UiRemoved' },
      { ' in ' .. theme.plural(block.files, 'file'), 'UiMuted' },
    })
  end

  if pixels then
    summary[#summary + 1] = { ' ' }
  else
    vim.list_extend(summary, { { ' ' }, { string.rep(theme.RULE, 2), 'UiTurnSeparator' } })
  end

  MarkSpec.add(out, block.start, 0, {
    virt_text = summary,
    virt_text_pos = 'right_align',
  })

  return out
end

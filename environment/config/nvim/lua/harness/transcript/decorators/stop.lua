local BlockBuilder = require('harness.transcript.BlockBuilder')
local MarkSpec = require('harness.transcript.MarkSpec')
local theme = require('harness.transcript.theme')

return function(block)
  local out = {}
  local icon = theme.STOP_ICONS[block.reason] or theme.STOP_FALLBACK_ICON
  local parts = { BlockBuilder.STOP_REASONS[block.reason] or tostring(block.reason) }
  local duration = theme.duration(block.duration)

  if duration then parts[1] = parts[1] .. ' in ' .. duration end
  if block.tools and block.tools > 0 then parts[#parts + 1] = theme.plural(block.tools, 'tool') end

  MarkSpec.add(out, block.start, 0, { end_col = #block.lines[1], conceal = '' })
  MarkSpec.add(out, block.start, 0, {
    virt_text = { icon, { table.concat(parts, ' · '), 'UiMuted' } },
    virt_text_pos = 'inline',
  })

  return out
end

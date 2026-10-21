local MarkSpec = require('ui.MarkSpec')
local PlanSummary = require('harness.transcript.PlanSummary')

local ENTRY_PREFIX = #'- [ ] '

return function(block)
  local out = {}

  MarkSpec.add(out, block.start, 0, { end_col = #block.lines[1], hl_group = 'UiMuted' })

  for index, status in ipairs(block.statuses or {}) do
    local row = block.start + index
    local line = block.lines[index + 1] or ''

    MarkSpec.add(out, row, 0, { end_col = math.min(ENTRY_PREFIX, #line), conceal = '' })
    MarkSpec.add(out, row, 0, { virt_text = { PlanSummary.mark(status) }, virt_text_pos = 'inline' })

    if status == 'completed' then MarkSpec.add(out, row, ENTRY_PREFIX, { end_col = #line, hl_group = 'UiMuted' }) end
  end

  return out
end

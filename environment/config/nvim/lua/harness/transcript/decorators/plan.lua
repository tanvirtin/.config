local MarkSpec = require('ui.MarkSpec')
local plan_summary = require('harness.transcript.plan_summary')

local ENTRY_PREFIX = #'- [ ] '

local function folded(out, block)
  local done = 0
  local total = #(block.statuses or {})

  for _, status in ipairs(block.statuses or {}) do
    if status == 'completed' then done = done + 1 end
  end

  MarkSpec.add(out, block.start, 0, {
    virt_text = { { string.format('  %d/%d ', done, total), 'UiMuted' }, { plan_summary.bar(done, total), 'UiAccent' } },
    virt_text_pos = 'eol',
  })

  for index = 1, total do
    MarkSpec.add(out, block.start + index, 0, { conceal_lines = '' })
  end
end

return function(block, ctx)
  local out = {}

  MarkSpec.add(out, block.start, 0, { end_col = #block.lines[1], hl_group = 'UiMuted' })

  if ctx and ctx.plan_open and block.statuses then
    folded(out, block)

    return out
  end

  for index, status in ipairs(block.statuses or {}) do
    local row = block.start + index
    local line = block.lines[index + 1] or ''

    MarkSpec.add(out, row, 0, { end_col = math.min(ENTRY_PREFIX, #line), conceal = '' })
    MarkSpec.add(out, row, 0, { virt_text = { plan_summary.mark(status) }, virt_text_pos = 'inline' })

    if status == 'completed' then MarkSpec.add(out, row, ENTRY_PREFIX, { end_col = #line, hl_group = 'UiMuted' }) end
  end

  return out
end

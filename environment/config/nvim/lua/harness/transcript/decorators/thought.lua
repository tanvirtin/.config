local MarkSpec = require('ui.MarkSpec')
local context = require('harness.transcript.decorators.context')
local theme = require('harness.transcript.theme')

return function(block, ctx)
  local out = {}
  local text

  if block.live and ctx.running then
    text = { { '  ' .. context.spinner(ctx) .. ' thinking', 'UiMuted' } }
  elseif block.started and block.finished then
    local duration = theme.duration(block.finished - block.started)
    if duration then text = { { '  ' .. duration, 'UiMuted' } } end
  end

  if text then MarkSpec.add(out, block.start, 0, { virt_text = text, virt_text_pos = 'eol' }) end

  return out
end

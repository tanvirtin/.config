local compact = require('compact')
local MarkSpec = require('ui.MarkSpec')
local nodes = require('ui.markdown.nodes')
local theme = require('harness.transcript.theme')

local CALLOUT = nodes.CALLOUTS.thought

local PEEK = 60

local function peek(block, ctx)
  for index = #block.lines, 2, -1 do
    local line = vim.trim(block.lines[index])

    if line ~= '' then return compact.line(line, math.min(PEEK, math.max((ctx.width or PEEK + 20) - 24, 12))) end
  end
end

return function(block, ctx)
  local out = {}
  local text
  local first = block.lines[1] or ''
  local pulsing = block.live and ctx.running
  local hl = pulsing and ctx.now and theme.pulse(ctx.now) or CALLOUT.hl

  MarkSpec.add(out, block.start, #(first:match('^[%s>]*') or ''), {
    virt_text = { { CALLOUT.icon, hl }, { CALLOUT.label, CALLOUT.hl } },
    virt_text_pos = 'inline',
  })

  if pulsing then
    text = { { '  ' .. theme.motion('thinking', ctx.now), 'UiMuted' } }

    local last = peek(block, ctx)

    if last then text[#text + 1] = { '  ' .. last, 'UiRailMuted' } end
  elseif block.started and block.finished then
    local duration = theme.duration(block.finished - block.started)
    if duration then text = { { '  ' .. duration, 'UiMuted' } } end
  end

  if text then MarkSpec.add(out, block.start, 0, { virt_text = text, virt_text_pos = 'eol' }) end

  return out
end

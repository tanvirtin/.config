local compact = require('compact')
local MarkSpec = require('ui.MarkSpec')
local nodes = require('ui.markdown.nodes')
local theme = require('harness.transcript.theme')

local CALLOUT = nodes.CALLOUTS.thought

local GIST = 72
local BODY_PRIORITY = 90

local function gist(block, ctx, latest)
  local first, last, step = 2, #block.lines, 1

  if latest then
    first, last, step = #block.lines, 2, -1
  end

  for index = first, last, step do
    local line = vim.trim((block.lines[index]:gsub('^[%s>]*', '')))

    if line ~= '' then
      local heading = line:match('^%*%*(.-)%*%*')
      local text = (heading and heading ~= '' and heading or line):gsub('[*`]', '')

      return compact.line(text, math.min(GIST, math.max((ctx.width or GIST + 24) - 24, 12)))
    end
  end
end

local function elapsed(block, ctx)
  local ms = math.max(0, ctx.now - block.started)

  return theme.duration(ms) or math.floor(ms / 1000) .. 's'
end

local function tail(block, ctx, pulsing)
  if pulsing then
    local out = {}
    local latest = gist(block, ctx, true)

    if block.started and ctx.now then out[#out + 1] = { '  ' .. elapsed(block, ctx), 'UiMuted' } end
    if latest then
      out[#out + 1] = { #out > 0 and ' · ' or '  ', 'UiMuted' }
      out[#out + 1] = { latest, 'UiThought' }
    end

    return out
  end

  local duration = block.started and block.finished and theme.duration(block.finished - block.started)
  local summary = gist(block, ctx)
  local out = {}

  if duration then out[#out + 1] = { '  ' .. duration, 'UiMuted' } end
  if summary then
    out[#out + 1] = { duration and ' · ' or '  ', 'UiMuted' }
    out[#out + 1] = { summary, 'UiThought' }
  end

  return out
end

return function(block, ctx)
  local out = {}
  local first = block.lines[1] or ''
  local pulsing = block.live and ctx.running
  local hl = pulsing and ctx.now and theme.pulse(ctx.now) or CALLOUT.hl

  MarkSpec.add(out, block.start, #(first:match('^[%s>]*') or ''), {
    virt_text = { { CALLOUT.icon, hl }, { CALLOUT.label, CALLOUT.hl } },
    virt_text_pos = 'inline',
  })

  local last = #block.lines

  if last > 1 and pulsing then
    for row = block.start + 1, block.start + last - 1 do
      MarkSpec.add(out, row, 0, { conceal_lines = '' })
    end
  elseif last > 1 then
    MarkSpec.add(out, block.start + 1, 0, {
      end_row = block.start + last - 1,
      end_col = #block.lines[last],
      hl_group = 'UiThought',
    }, BODY_PRIORITY)
  end

  local text = tail(block, ctx, pulsing)

  if #text > 0 then MarkSpec.add(out, block.start, 0, { virt_text = text, virt_text_pos = 'eol' }) end

  return out
end

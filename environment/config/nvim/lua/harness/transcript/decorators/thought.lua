local compact = require('compact')
local glitch = require('ui.glitch')
local design = require('ui.design')
local MarkSpec = require('ui.MarkSpec')
local layer = require('ui.design.layer')
local glyph = require('ui.design.glyph')
local nodes = require('ui.markdown.nodes')
local theme = require('harness.transcript.theme')

local CALLOUT = nodes.CALLOUTS.thought

local GIST = 72
local BODY_PRIORITY = layer.of('body')
local THOUGHT_TAIL = 3
local FADES = { 'UiThoughtFade2', 'UiThoughtFade1', 'UiThought' }
local STATIC = 'whisper'

local function gist(block, ctx)
  for index = 2, #block.lines do
    local line = vim.trim((block.lines[index]:gsub('^[%s>]*', '')))

    if line ~= '' then
      local heading = line:match('^%*%*(.-)%*%*')
      local text = (heading and heading ~= '' and heading or line):gsub('[*`]', '')

      return compact.line(text, math.min(GIST, math.max((ctx.width or GIST + 24) - 24, 12)))
    end
  end
end

local function interference(out, block, index, ctx)
  if theme.reduced() or not ctx.now then return end

  local line = block.lines[index]
  local from = #(line:match('^[%s>]*') or '')

  for _, cell in ipairs(glitch.cols(line, design.static.density(STATIC), design.static.seed(ctx.now, true), from)) do
    MarkSpec.add(out, block.start + index - 1, cell[1], {
      virt_text = { { cell[2], FADES[1] } },
      virt_text_pos = 'overlay',
    }, layer.of('effect'))
  end
end

local function elapsed(block, ctx)
  local ms = math.max(0, ctx.now - block.started)

  return theme.duration(ms) or math.floor(ms / 1000) .. 's'
end

local function tail(block, ctx, pulsing)
  if pulsing then
    if not (block.started and ctx.now) then return {} end

    return { { '  ' .. elapsed(block, ctx), 'UiMuted' } }
  end

  local duration = block.started and block.finished and theme.duration(block.finished - block.started)
  local summary = gist(block, ctx)
  local out = {}

  if duration then out[#out + 1] = { '  for ' .. duration, 'UiMuted' } end
  if summary then
    out[#out + 1] = { duration and glyph.SEPARATOR or '  ', 'UiMuted' }
    out[#out + 1] = { summary, 'UiThought' }
  end

  return out
end

return function(block, ctx)
  local out = {}
  local first = block.lines[1] or ''
  local pulsing = block.live and ctx.running
  local icon = pulsing and theme.loader('thinking', ctx.now) or { CALLOUT.icon, CALLOUT.hl }
  local label = pulsing and 'Thinking' or CALLOUT.label
  local header = { { label, CALLOUT.hl } }

  if icon[1] ~= '' then table.insert(header, 1, icon) end

  MarkSpec.add(out, block.start, #(first:match('^[%s>]*') or ''), {
    virt_text = header,
    virt_text_pos = 'inline',
  })

  local last = #block.lines
  local revealed = ctx.revealed and block.first_event and ctx.revealed[block.first_event]

  if last > 1 and pulsing and not revealed then
    local visible = math.min(THOUGHT_TAIL, last - 1)

    for index = 2, last - visible do
      MarkSpec.add(out, block.start + index - 1, 0, { conceal_lines = '' })
    end

    for index = last - visible + 1, last do
      local group = FADES[#FADES - (last - index)]

      MarkSpec.add(out, block.start + index - 1, 0, {
        end_col = #block.lines[index],
        hl_group = group,
      }, BODY_PRIORITY)
    end

    if last - 1 > visible then interference(out, block, last - visible + 1, ctx) end
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

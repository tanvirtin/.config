local text = require('core.text')
local MarkSpec = require('ui.MarkSpec')
local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')
local context = require('harness.transcript.decorators.context')

local function count_lines(output)
  local trimmed = (output or ''):gsub('%s+$', '')

  if trimmed == '' then return 0 end

  return select(2, trimmed:gsub('\n', '')) + 1
end

local SUMMARY = {
  [Block.CATEGORY.read] = function(block)
    local n = count_lines(block.output)
    return n > 0 and theme.plural(n, 'line') or nil
  end,
  [Block.CATEGORY.search] = function(block)
    return theme.plural(count_lines(block.output), 'result')
  end,
}

local function icon_of(block, ctx, live, waiting)
  if waiting then return theme.WAITING_ICON end
  if live then return { context.spinner(ctx) .. ' ', 'UiToolPending' } end
  if block.interrupted then return { theme.TOOL_ICONS.failed[1], 'UiMuted' } end

  return theme.TOOL_ICONS[block.status] or theme.TOOL_ICONS[Block.STATUS.pending]
end

local function verb_of(block)
  local verb = block.grouped and block.name:sub(1, 1):lower() .. block.name:sub(2) or block.name:lower()

  if not block.argument then return verb end

  return verb .. string.rep(' ', math.max(theme.VERB_WIDTH - text.width(verb), 2))
end

local function subagent_summary(block, live)
  local tools = theme.plural(block.nested, 'tool')

  if live or not context.FINISHED[block.status] or block.finished == nil then return tools end

  local duration = block.started and theme.duration(block.finished - block.started)

  return (duration and duration .. ' · ' or '') .. tools
end

local function tail_of(block, ctx, live, waiting)
  local parts = {}

  local function add(...)
    if #parts > 0 then parts[#parts + 1] = { '  ' } end

    for _, chunk in ipairs({ ... }) do
      parts[#parts + 1] = chunk
    end
  end

  if block.nested then add({ subagent_summary(block, live), 'UiMuted' }) end
  if block.added or block.removed then
    add({ '+' .. (block.added or 0), 'UiAdded' }, { ' ' }, { '−' .. (block.removed or 0), 'UiRemoved' })
  end

  if block.denied then
    add({ block.denied, 'UiWarn' })
  elseif block.interrupted and not live then
    add({ 'interrupted', 'UiMuted' })
  end

  if waiting then
    add({ 'waiting for you', 'UiWarn' })
  elseif live and block.started and ctx.now then
    local elapsed = theme.duration(ctx.now - block.started)
    if elapsed then add({ elapsed, 'UiMuted' }) end
  elseif not live and context.FINISHED[block.status] and SUMMARY[block.category] and #block.lines == 1 then
    local summary = SUMMARY[block.category](block)
    if summary then add({ summary, 'UiMuted' }) end
  end

  return parts
end

local function width_of(chunks)
  local width = 0

  for _, chunk in ipairs(chunks) do
    width = width + text.width(chunk[1])
  end

  return width
end

local function tail_position(block, head, tail, ctx)
  if not ctx.width or block.first_child then return 'eol' end

  return head + width_of(tail) + 2 <= ctx.width and 'right_align' or 'eol'
end

return function(block, ctx)
  local out = {}
  local row = block.start
  local live = context.live_tool(block, ctx)
  local waiting = live and context.waiting_for(block, ctx)
  local icon = icon_of(block, ctx, live, waiting)
  local verb = verb_of(block)
  local hidden = 3 + #block.name + (block.argument and 1 or 0)

  MarkSpec.add(out, row, 0, { end_col = math.min(hidden, #block.lines[1]), conceal = '' })
  MarkSpec.add(out, row, 0, { virt_text = { icon, { verb, 'UiToolName' } }, virt_text_pos = 'inline' })

  local tail = tail_of(block, ctx, live, waiting)

  if #tail > 0 then
    local head = width_of({ icon, { verb } })
      + text.width(block.argument or '')
      + (block.depth and text.width(theme.GUTTER) or 0)
    local position = tail_position(block, head, tail, ctx)

    if position == 'eol' then table.insert(tail, 1, { '  ' }) end

    MarkSpec.add(out, row, 0, { virt_text = tail, virt_text_pos = position })
  end

  if #block.lines > 1 then
    local failed = block.status == Block.STATUS.failed

    for body_row = row + 2, block.start + #block.lines - 2 do
      MarkSpec.add(out, body_row, 0, { virt_text = { { theme.GUTTER, 'UiMuted' } }, virt_text_pos = 'inline' })

      if failed then
        MarkSpec.add(out, body_row, 0, { end_row = body_row + 1, hl_group = 'UiError', hl_eol = false })
      end
    end
  end

  return out
end

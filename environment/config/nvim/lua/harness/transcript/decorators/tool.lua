local Block = require('harness.transcript.Block')
local MarkSpec = require('ui.MarkSpec')
local context = require('harness.transcript.decorators.context')
local theme = require('harness.transcript.theme')

local function count_lines(text)
  local trimmed = (text or ''):gsub('%s+$', '')

  if trimmed == '' then return 0 end

  return select(2, trimmed:gsub('\n', '')) + 1
end

local SUMMARY = {
  [Block.CATEGORY.read] = function(block)
    local n = count_lines(block.output)
    return n > 0 and 'Read ' .. theme.plural(n, 'line') or nil
  end,
  [Block.CATEGORY.search] = function(block)
    return theme.plural(count_lines(block.output), 'result')
  end,
}

local function icon_of(block, ctx, live, waiting)
  if waiting then return theme.WAITING_ICON end
  if live then return { context.spinner(ctx) .. ' ', 'UiToolPending' } end

  return theme.TOOL_ICONS[block.status] or theme.TOOL_ICONS[Block.STATUS.pending]
end

local function subagent_summary(block, live)
  local tools = theme.plural(block.nested, 'tool')

  if live or not context.FINISHED[block.status] then return tools end
  if block.finished == nil then return tools end

  local failed = block.status == Block.STATUS.failed
  local duration = block.started and block.finished and theme.duration(block.finished - block.started)

  return (failed and 'failed' or 'done') .. (duration and ' in ' .. duration or '') .. ' · ' .. tools
end

local function tail_of(block, ctx, live, waiting)
  local tail = {}

  if block.nested then tail[#tail + 1] = { subagent_summary(block, live), 'UiMuted' } end

  if block.added or block.removed then
    if #tail > 0 then tail[#tail + 1] = { '  ' } end
    tail[#tail + 1] = { '+' .. (block.added or 0), 'UiAdded' }
    tail[#tail + 1] = { ' ' }
    tail[#tail + 1] = { '-' .. (block.removed or 0), 'UiRemoved' }
  end

  if waiting then
    tail[#tail + 1] = { (#tail > 0 and '  ' or '') .. 'waiting for you', 'UiWarn' }
  elseif live and block.started and ctx.now then
    local elapsed = theme.duration(ctx.now - block.started)
    if elapsed then tail[#tail + 1] = { (#tail > 0 and '  ' or '') .. elapsed, 'UiMuted' } end
  end

  if #tail > 0 then table.insert(tail, 1, { '  ' }) end

  return tail
end

return function(block, ctx)
  local out = {}
  local row = block.start
  local live = context.live_tool(block, ctx)
  local waiting = live and context.waiting_for(block, ctx)

  MarkSpec.add(out, row, 0, { end_col = 3, conceal = '' })
  MarkSpec.add(out, row, 0, { virt_text = { icon_of(block, ctx, live, waiting) }, virt_text_pos = 'inline' })
  MarkSpec.add(out, row, 3, { end_col = 3 + #block.name, hl_group = 'UiToolName' })

  local tail = tail_of(block, ctx, live, waiting)

  if #tail > 0 then MarkSpec.add(out, row, 0, { virt_text = tail, virt_text_pos = 'eol' }) end

  if #block.lines > 1 then
    local failed = block.status == Block.STATUS.failed

    for body_row = row + 2, block.start + #block.lines - 2 do
      MarkSpec.add(out, body_row, 0, {
        virt_text = { { body_row == row + 2 and '⎿ ' or '  ', 'UiMuted' } },
        virt_text_pos = 'inline',
      })

      if failed then
        MarkSpec.add(out, body_row, 0, { end_row = body_row + 1, hl_group = 'UiError', hl_eol = false })
      end
    end
  elseif context.FINISHED[block.status] and SUMMARY[block.category] then
    local summary = SUMMARY[block.category](block)

    if summary then
      local line = { { '  ⎿ ', 'UiMuted' }, { summary, 'UiMuted' } }

      if block.depth then table.insert(line, 1, { theme.GUTTER, 'UiMuted' }) end

      MarkSpec.add(out, row, 0, { virt_lines = { line } })
    end
  end

  return out
end

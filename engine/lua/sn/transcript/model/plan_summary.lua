local text = require('core.text')
local compact = require('compact')
local theme = require('sn.transcript.theme')
local EVENT = require('sn.types.events').KIND
local Block = require('sn.transcript.model.Block')

local plan_summary = {}

plan_summary.MAX_WIDTH = 50

function plan_summary.mark(status)
  local icons = theme.PLAN_ICONS

  return icons[status] or icons.pending
end

function plan_summary.latest(history)
  for i = #history, 1, -1 do
    local event = history[i]

    if event.kind == EVENT.plan then return event.entries or {} end
  end
end

function plan_summary.done(entries)
  local count = 0

  for _, entry in ipairs(entries) do
    if entry.status == Block.STATUS.completed then count = count + 1 end
  end

  return count
end

function plan_summary.unfinished(entries)
  return entries ~= nil and #entries > 0 and plan_summary.done(entries) < #entries
end

plan_summary.BAR = { full = '▰', empty = '▱', width = 8 }

function plan_summary.bar(done, total, width)
  width = width or plan_summary.BAR.width

  local filled = total > 0 and math.floor(done / total * width + 0.5) or 0

  return string.rep(plan_summary.BAR.full, filled) .. string.rep(plan_summary.BAR.empty, width - filled)
end

function plan_summary.render(entries)
  local done = plan_summary.done(entries)
  local head = string.format(' Plan  %d/%d ', done, #entries)
  local title = head .. plan_summary.bar(done, #entries)
  local lines = { title }
  local highlights = { { row = 0, from = 0, to = #title, hl = 'UiTitle' } }
  local width = text.width(title)

  for i, entry in ipairs(entries) do
    local mark = plan_summary.mark(entry.status)
    local prefix = ' ' .. mark[1]
    local content = compact.line(entry.content or '', plan_summary.MAX_WIDTH - text.width(prefix) - 1)
    local line = prefix .. content

    lines[#lines + 1] = line
    highlights[#highlights + 1] = { row = i, from = 0, to = #prefix, hl = mark[2] }

    if entry.status == Block.STATUS.completed then
      highlights[#highlights + 1] = { row = i, from = #prefix, to = #line, hl = 'UiMuted' }
    end

    width = math.max(width, text.width(line))
  end

  local bar = {
    row = 0,
    col = #head,
    done = done,
    total = #entries,
    width = plan_summary.BAR.width,
  }

  return { lines = lines, highlights = highlights, width = width + 1, bar = bar }
end

return plan_summary

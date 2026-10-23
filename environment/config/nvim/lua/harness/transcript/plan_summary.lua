local text = require('core.text')
local compact = require('compact')
local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')
local EVENT = require('harness.types.events').KIND

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

function plan_summary.render(entries)
  local title = string.format(' Plan  %d/%d', plan_summary.done(entries), #entries)
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

  return { lines = lines, highlights = highlights, width = width + 1 }
end

return plan_summary

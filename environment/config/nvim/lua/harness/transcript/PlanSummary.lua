local Block = require('harness.transcript.Block')
local EVENT = require('harness.events').KIND
local compact = require('compact')
local text = require('core.text')

local PlanSummary = {}

PlanSummary.MAX_WIDTH = 50

PlanSummary.MARKS = {
  [Block.STATUS.completed] = { '󰄬 ', 'UiMuted' },
  [Block.STATUS.in_progress] = { '󰔟 ', 'UiAccent' },
}

PlanSummary.PENDING = { '○ ', 'UiMuted' }

function PlanSummary.latest(history)
  for i = #history, 1, -1 do
    local event = history[i]

    if event.kind == EVENT.plan then return event.entries or {} end
  end
end

function PlanSummary.done(entries)
  local count = 0

  for _, entry in ipairs(entries) do
    if entry.status == Block.STATUS.completed then count = count + 1 end
  end

  return count
end

function PlanSummary.unfinished(entries)
  return entries ~= nil and #entries > 0 and PlanSummary.done(entries) < #entries
end

function PlanSummary.render(entries)
  local title = string.format(' Plan  %d/%d', PlanSummary.done(entries), #entries)
  local lines = { title }
  local highlights = { { row = 0, from = 0, to = #title, hl = 'UiTitle' } }
  local width = text.width(title)

  for i, entry in ipairs(entries) do
    local mark = PlanSummary.MARKS[entry.status] or PlanSummary.PENDING
    local prefix = ' ' .. mark[1]
    local content = compact.line(entry.content or '', PlanSummary.MAX_WIDTH - text.width(prefix) - 1)
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

return PlanSummary

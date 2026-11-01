local ask = require('harness.transcript.status_line.ask')
local card = require('harness.transcript.status_line.card')
local queue = require('harness.transcript.status_line.queue')
local replay = require('harness.transcript.status_line.replay')
local closing = require('harness.transcript.status_line.closing')
local working = require('harness.transcript.status_line.working')
local subagents = require('harness.transcript.status_line.subagents')

local status_line = {}

status_line.RAIL = card.RAIL
status_line.card_of = card.of
status_line.closing_ms = closing.ms
status_line.closing_rows = closing.rows

local sections = {}

function status_line.register(section)
  status_line.unregister(section.id)
  sections[#sections + 1] = section

  table.sort(sections, function(a, b)
    return a.order < b.order
  end)

  return status_line
end

function status_line.unregister(id)
  for index, existing in ipairs(sections) do
    if existing.id == id then
      table.remove(sections, index)
      break
    end
  end

  return status_line
end

function status_line.sections()
  return vim.list_slice(sections)
end

for _, section in ipairs({ closing, ask, replay, subagents, queue.held, working, queue }) do
  status_line.register(section)
end

function status_line.lines(state, now)
  local rows, claimed = {}, false

  for _, section in ipairs(sections) do
    if not (claimed and section.exclusive) and section.applies(state) then
      vim.list_extend(rows, section.lines(state, now))
      claimed = claimed or section.exclusive
    end
  end

  if #rows == 0 then return nil end

  table.insert(rows, 1, { { '' } })

  return rows
end

return status_line

local hl = require('ui.hl')
local tone = require('ui.tone')
local motion = require('ui.motion')
local settings = require('harness.settings.transcript')
local card = require('harness.transcript.status_line.card')

local closing = { id = 'closing', order = 10, exclusive = false }

function closing.ms()
  return settings:get('flash_ms') * 2
end

function closing.applies(state)
  return state.closing ~= nil and #(state.asks or {}) == 0
end

function closing.rows(shown, now)
  local ms = closing.ms()
  local progress = ms > 0 and (now - shown.started) / ms or 1

  if progress >= 1 then return {} end

  local step, count = hl.FLASH_STEPS, #shown.lines

  if progress < 0.5 then
    step = motion.steps(hl.FLASH_STEPS, motion.ease.out_cubic(progress * 2))
  else
    count = math.ceil(count * (1 - motion.ease.in_out((progress - 0.5) * 2)))
  end

  local flash = tone.flash(shown.tone, step)
  local rows = {}

  for index = 1, count do
    local row = {}

    for _, chunk in ipairs(shown.lines[index]) do
      row[#row + 1] = { chunk[1], card.retint(chunk[2], flash) }
    end

    rows[#rows + 1] = row
  end

  return rows
end

function closing.lines(state, now)
  return closing.rows(state.closing, now or 0)
end

return closing

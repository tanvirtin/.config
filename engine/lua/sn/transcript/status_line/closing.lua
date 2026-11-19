local hl = require('ui.hl')
local tone = require('ui.tone')
local glitch = require('ui.glitch')
local motion = require('ui.motion')
local design = require('ui.design')
local glyph = require('ui.design.glyph')
local settings = require('sn.settings.transcript')
local card = require('sn.transcript.status_line.card')

local closing = { id = 'closing', order = 10, exclusive = false }

closing.FLASH = 0.4
closing.SQUASH = 0.75
closing.DOT = 0.92
closing.STATIC = 'heavy'

function closing.ms()
  return settings:get('flash_ms')
end

function closing.applies(state)
  return state.closing ~= nil and #(state.asks or {}) == 0
end

local function width(line)
  local total = 1

  for index = 2, #line do
    total = total + select(2, line[index][1]:gsub('[^\128-\191]', ''))
  end

  return total
end

local function flash(shown, progress)
  local step = motion.steps(hl.FLASH_STEPS, motion.ease.out_cubic(progress / closing.FLASH))
  local group = tone.flash(shown.tone, step)
  local rows = {}

  for _, line in ipairs(shown.lines) do
    local row = {}

    for _, chunk in ipairs(line) do
      row[#row + 1] = { chunk[1], card.retint(chunk[2], group) }
    end

    rows[#rows + 1] = row
  end

  return rows
end

local function squash(shown, progress, now)
  local t = (progress - closing.FLASH) / (closing.SQUASH - closing.FLASH)
  local count = math.max(1, math.ceil(#shown.lines * (1 - motion.ease.in_out(t))))
  local group = tone.flash(shown.tone, hl.FLASH_STEPS)
  local seed = design.static.seed(now)
  local rows = {}

  for index = 1, count do
    local row = {}

    for _, chunk in ipairs(shown.lines[index]) do
      row[#row + 1] = {
        glitch.scramble(chunk[1], design.static.density(closing.STATIC, t), seed + index),
        card.retint(chunk[2], group),
      }
    end

    rows[#rows + 1] = row
  end

  return rows
end

local function line(shown, progress)
  local full = width(shown.lines[1] or {})
  local group = tone.flash(shown.tone, 1)

  if progress >= closing.DOT then return { { { string.rep(' ', math.floor(full / 2)) .. glyph.DOT, group } } } end

  local t = (progress - closing.SQUASH) / (closing.DOT - closing.SQUASH)
  local length = math.max(1, math.floor(full * (1 - motion.ease.in_out(t))))

  return { { { string.rep(' ', math.floor((full - length) / 2)) .. string.rep(glyph.LINE.heavy, length), group } } }
end

function closing.rows(shown, now)
  local ms = closing.ms()
  local progress = ms > 0 and (now - shown.started) / ms or 1

  if progress >= 1 then return {} end
  if progress < closing.FLASH then return flash(shown, progress) end
  if progress < closing.SQUASH then return squash(shown, progress, now) end

  return line(shown, progress)
end

function closing.lines(state, now)
  return closing.rows(state.closing, now or 0)
end

return closing

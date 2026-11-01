local tone = require('ui.tone')
local text = require('core.text')
local theme = require('harness.transcript.theme')

local card = {}

card.RAIL = '▎'

local SURFACE = tone.surface(tone.WARN)

local function shaded(group)
  if type(group) == 'table' then return vim.list_extend(vim.list_slice(group), { SURFACE }) end

  if group == 'UiAccent' then return { group, 'UiSurfaceRaised' } end

  return { group or 'UiMuted', SURFACE }
end

function card.build(state, lines, now)
  local out = {}

  for index = 1, #lines do
    local line, card_line = lines[index], {}
    local indent = line[1] and line[1][1] == '   '
    local rail = now and theme.pulse(now, tone.WARN) or tone.rail(tone.WARN)

    card_line[1] = { indent and card.RAIL .. '  ' or card.RAIL, { rail, SURFACE } }

    for chunk_index = indent and 2 or 1, #line do
      local chunk = line[chunk_index]

      if chunk then card_line[#card_line + 1] = { chunk[1], shaded(chunk[2]) } end
    end

    local used = 0

    for _, chunk in ipairs(card_line) do
      used = used + text.width(chunk[1])
    end

    if state.width and used < state.width then
      card_line[#card_line + 1] = { string.rep(' ', state.width - used), SURFACE }
    end

    out[#out + 1] = card_line
  end

  return out
end

function card.of(lines)
  local rows = {}

  for _, line in ipairs(lines or {}) do
    local first = line[1] and line[1][1]

    if type(first) == 'string' and first:sub(1, #card.RAIL) == card.RAIL then rows[#rows + 1] = line end
  end

  return rows
end

function card.retint(group, flash)
  if group == SURFACE then return flash end
  if type(group) ~= 'table' then return group end

  local out = {}

  for _, name in ipairs(group) do
    out[#out + 1] = name == SURFACE and flash or name
  end

  return out
end

return card

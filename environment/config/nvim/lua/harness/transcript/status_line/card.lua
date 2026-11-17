local tone = require('ui.tone')
local text = require('core.text')
local glyph = require('ui.design.glyph')
local theme = require('harness.transcript.theme')
local indicators = require('ui.pixel.indicators')

local card = {}

card.RAIL = glyph.LINE.rail

local SURFACE = tone.surface(tone.WARN)
local rows = setmetatable({}, { __mode = 'k' })

local function shaded(group)
  if type(group) == 'table' then return vim.list_extend(vim.list_slice(group), { SURFACE }) end

  if group == 'UiAccent' then return { group, 'UiSurfaceRaised' } end

  return { group or 'UiMuted', SURFACE }
end

function card.build(state, lines, now)
  local out = {}
  local pixels = now and not theme.reduced()

  for index = 1, #lines do
    local line, card_line = lines[index], {}
    local indent = line[1] and line[1][1] == '   '
    local pixel = pixels and indicators.chunk('rail', 'warn', index, #lines)

    if pixel then
      card_line[1], card_line[2] = pixel, { indent and '  ' or '', SURFACE }
    else
      card_line[1] = { indent and card.RAIL .. '  ' or card.RAIL, { tone.rail(tone.WARN), SURFACE } }
    end

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

    rows[card_line] = true
    out[#out + 1] = card_line
  end

  return out
end

function card.of(lines)
  local found = {}

  for _, line in ipairs(lines or {}) do
    local first = line[1] and line[1][1]

    if rows[line] or (type(first) == 'string' and first:sub(1, #card.RAIL) == card.RAIL) then
      found[#found + 1] = line
    end
  end

  return found
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

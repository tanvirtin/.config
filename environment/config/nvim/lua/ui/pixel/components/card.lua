local text = require('core.text')
local markup = require('ui.markup')
local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')

local max, min = math.max, math.min

local INSET_X, INSET_Y = 7, 15
local WIDTH = 2
local RADIUS = 8

local function strings(lines)
  local out = {}

  for _, line in ipairs(lines) do
    if type(line) == 'string' then out[#out + 1] = line end
  end

  return out
end

local function rule(tiles, border, cols, oy)
  local chunks = {}

  for start = 0, cols - 1, Tile.MAX_CELLS do
    local tile = tiles:add(min(Tile.MAX_CELLS, cols - start), 1, { border }, start * Tile.CELL[1], oy)

    chunks[#chunks + 1] = tile:chunks(1)[1]
  end

  return chunks
end

local function edge(tiles, border, rows, ox)
  local chunks = {}

  for start = 0, rows - 1, Tile.MAX_CELLS do
    local count = min(Tile.MAX_CELLS, rows - start)
    local tile = tiles:add(1, count, { border }, ox, (start + 1) * Tile.CELL[2])

    for row = 1, count do
      chunks[#chunks + 1] = tile:chunks(row)[1]
    end
  end

  return chunks
end

return {
  name = 'card',
  props = {
    lines = { 'table', {} },
    color = { 'string', 'muted' },
  },
  render = function(props, tiles)
    local lines = strings(props.lines)

    if #lines == 0 then return {} end

    local w, h = 0, #lines
    local padded = {}

    for _, line in ipairs(lines) do
      w = max(w, text.width(line))
    end

    for i, line in ipairs(lines) do
      padded[i] = line .. string.rep(' ', w - text.width(line))
    end

    local rows = {}

    if tiles.pixels then
      local border = {
        kind = 'border',
        x = INSET_X,
        y = INSET_Y,
        w = (w + 2) * Tile.CELL[1] - 2 * INSET_X,
        h = (h + 2) * Tile.CELL[2] - 2 * INSET_Y,
        width = WIDTH,
        radius = RADIUS,
        color = roles.rgb(props.color),
      }
      local left = edge(tiles, border, h, 0)
      local right = edge(tiles, border, h, (w + 1) * Tile.CELL[1])

      rows[1] = rule(tiles, border, w + 2, 0)

      for i = 1, h do
        rows[#rows + 1] = { left[i], { padded[i] }, right[i] }
      end

      rows[#rows + 1] = rule(tiles, border, w + 2, (h + 1) * Tile.CELL[2])

      return rows
    end

    local group = markup.group(props.color)

    rows[1] = { { '╭' .. string.rep('─', w) .. '╮', group } }

    for i = 1, h do
      rows[#rows + 1] = { { '│', group }, { padded[i] }, { '│', group } }
    end

    rows[#rows + 1] = { { '╰' .. string.rep('─', w) .. '╯', group } }

    return rows
  end,
}

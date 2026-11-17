local Tile = require('ui.pixel.Tile')
local Tiles = require('ui.pixel.Tiles')
local Bitmap = require('ui.pixel.Bitmap')
local static = require('ui.pixel.static')
local catalog = require('ui.pixel.catalog')
local highlight = require('core.highlight')
local indicators = require('ui.pixel.indicators')

local floor, min, max = math.floor, math.min, math.max

local meter = {}

meter.SQUARES = 5
meter.DIFFSTAT_COLS = 3

local SQUARE, GAP, RADIUS = 8, 2, 2
local RING_INSET = 4
local ADDED, REMOVED = 'UiAdded', 'UiRemoved'

local tiles
local cache = {}

local function pool()
  tiles = tiles or Tiles()

  return tiles
end

local function fg_of(group)
  return highlight.get_hl_by_name(group).fg
end

local function chunk_of(key, cols, build)
  local tile = cache[key]

  if not tile then
    tile = pool():add(cols, 1, build())
    cache[key] = tile
  end

  return { tile:chunks(1)[1] }
end

function meter.bar(value, cols, group)
  if not Tile.available() then return nil end

  local fg = fg_of(group)

  if not fg then return nil end

  value = max(0, min(1, value))

  local key = 'bar:' .. cols .. ':' .. floor(value * cols * Tile.CELL[1] + 0.5) .. ':' .. fg

  return chunk_of(key, cols, function()
    local props = catalog.resolve('bar', { value = value, cols = cols, color = string.format('#%06x', fg) })

    return catalog.get('bar').commands(props, cols * Tile.CELL[1], Tile.CELL[2], 0)
  end)
end

local function draw_ring(bitmap, command)
  local n = indicators.SPIN_GRID
  local c = (n - 1) / 2
  local seed = floor(command.value * 100 + 0.5)
  local full = command.value >= 0.9

  for y = 0, n - 1 do
    for x = 0, n - 1 do
      if indicators.on_ring(x, y) then
        local angle = math.atan2(x - c, c - y) % (2 * math.pi)
        local filled = angle / (2 * math.pi) < command.value
        local h = static.hash(x, y, seed)
        local alpha

        if filled then
          alpha = h < (full and 24 or 8) and 0.35 or 1
        elseif h < 40 then
          alpha = 0.2
        end

        if alpha then bitmap:rect(RING_INSET + x * 2, RING_INSET + y * 2, 2, 2, command.color, alpha) end
      end
    end
  end
end

function meter.ring(value, group)
  if not Tile.available() then return nil end

  local fg = fg_of(group)

  if not fg then return nil end

  value = max(0, min(1, value))

  local key = 'ring:' .. floor(value * 100 + 0.5) .. ':' .. fg

  return chunk_of(key, 2, function()
    return { { kind = 'custom', draw = draw_ring, value = value, color = Bitmap.rgb(fg) } }
  end)
end

function meter.greens(added, removed)
  local total = added + removed

  if total == 0 then return 0 end

  local greens = floor(added / total * meter.SQUARES + 0.5)

  if added > 0 then greens = max(greens, 1) end
  if removed > 0 then greens = min(greens, meter.SQUARES - 1) end

  return greens
end

function meter.diffstat(added, removed)
  if added + removed == 0 or not Tile.available() then return nil end

  local added_fg, removed_fg = fg_of(ADDED), fg_of(REMOVED)

  if not added_fg or not removed_fg then return nil end

  local greens = meter.greens(added, removed)
  local key = 'diff:' .. greens .. ':' .. added_fg .. ':' .. removed_fg

  return chunk_of(key, meter.DIFFSTAT_COLS, function()
    local commands = {}
    local y = (Tile.CELL[2] - SQUARE) / 2

    for index = 1, meter.SQUARES do
      commands[index] = {
        kind = 'rectangle',
        x = (index - 1) * (SQUARE + GAP),
        y = y,
        w = SQUARE,
        h = SQUARE,
        radius = RADIUS,
        color = Bitmap.rgb(index <= greens and added_fg or removed_fg),
      }
    end

    return commands
  end)
end

function meter.count()
  local total = 0

  for _ in pairs(cache) do
    total = total + 1
  end

  return total
end

function meter.stop()
  if tiles then tiles:release() end

  tiles = nil
  cache = {}
end

return meter

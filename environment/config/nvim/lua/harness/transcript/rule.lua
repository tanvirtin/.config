local design = require('ui.design')
local Tile = require('ui.pixel.Tile')
local Tiles = require('ui.pixel.Tiles')
local Bitmap = require('ui.pixel.Bitmap')
local static = require('ui.pixel.static')
local highlight = require('core.highlight')

local floor, min = math.floor, math.min

local rule = {}

rule.FADE = 6
rule.STYLES = { static = 'static', faint = 'faint' }
rule.BLOCK = 2

local cache = {}

local function total_px()
  return (rule.FADE * 2 + Tile.MAX_CELLS) * Tile.CELL[1]
end

local function strength(px)
  local fade_px = rule.FADE * Tile.CELL[1]

  return min(1, px / fade_px, (total_px() - px) / fade_px)
end

local function noise(preset, rows)
  return function(rgb)
    return function(bitmap, command)
      local density = design.static.density(preset) * 100
      local mid = Tile.CELL[2] / 2

      for px = 0, total_px() - 1, rule.BLOCK do
        local x = command.x + px
        local column = math.floor(px / rule.BLOCK)

        if x >= -2 and x <= bitmap.width + 2 then
          for row = 0, rows - 1 do
            local h = static.hash(column, row, 7)

            if h < density then
              local y = mid - rows * rule.BLOCK / 2 + row * rule.BLOCK

              bitmap:rect(x, y, rule.BLOCK, rule.BLOCK, rgb, strength(px) * (0.35 + 0.65 * h / density))
            end
          end
        end
      end
    end
  end
end

local DRAW = { static = noise('medium', 2), faint = noise('whisper', 1) }

local function build(style, fg)
  local commands = { { kind = 'custom', x = 0, y = 0, draw = DRAW[style](Bitmap.rgb(fg)) } }
  local tiles = Tiles()
  local body_x = rule.FADE * Tile.CELL[1]

  return {
    fg = fg,
    tiles = tiles,
    left = tiles:add(rule.FADE, 1, commands, 0, 0),
    body = tiles:add(Tile.MAX_CELLS, 1, commands, body_x, 0),
    right = tiles:add(rule.FADE, 1, commands, body_x + Tile.MAX_CELLS * Tile.CELL[1], 0),
  }
end

function rule.chunks(width, group, style)
  style = style or rule.STYLES.static

  if not Tile.available() or width < 2 * rule.FADE + 1 then return nil end

  local fg = highlight.get_hl_by_name(group).fg

  if not fg then return nil end

  local entry = cache[style]

  if entry and entry.fg ~= fg then
    entry.tiles:release()
    entry = nil
  end

  if not entry then
    entry = build(style, fg)
    cache[style] = entry
  end

  local cells = width - 2 * rule.FADE
  local body = entry.body:chunks(1)[1]
  local text = string.rep(body[1], floor(cells / Tile.MAX_CELLS))

  if cells % Tile.MAX_CELLS ~= 0 then text = text .. entry.body:chunks(1, cells % Tile.MAX_CELLS)[1][1] end

  return { entry.left:chunks(1)[1], { text, body[2] }, entry.right:chunks(1)[1] }
end

function rule.count()
  local total = 0

  for _ in pairs(cache) do
    total = total + 1
  end

  return total
end

function rule.stop()
  for _, entry in pairs(cache) do
    entry.tiles:release()
  end

  cache = {}
end

return rule

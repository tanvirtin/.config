local hl = require('ui.hl')
local text = require('core.text')
local Tile = require('ui.pixel.Tile')
local roles = require('ui.pixel.roles')
local Bitmap = require('ui.pixel.Bitmap')
local highlight = require('core.highlight')

local INSET = 6
local RADIUS = 10
local TINT = 0.22

return {
  name = 'badge',
  props = {
    text = { 'string', '' },
    color = { 'string', 'accent' },
  },
  render = function(props, tiles)
    if props.text == '' then return {} end

    local fg = roles.resolve(props.color)
    local normal = highlight.get_hl_by_name('Normal').bg
    local group = string.format('UiPixelBadge%06x', fg)

    if not tiles.pixels or not normal then
      highlight.set(group, { fg = fg })

      return { { { ' ' .. props.text .. ' ', group } } }
    end

    local bg = hl.blend(fg, normal, TINT)
    local width = text.width(props.text)
    local pill = {
      kind = 'rectangle',
      x = INSET,
      y = 0,
      w = (width + 2) * Tile.CELL[1] - 2 * INSET,
      h = Tile.CELL[2],
      radius = RADIUS,
      color = Bitmap.rgb(bg),
      opacity = 1,
    }

    highlight.set(group, { fg = fg, bg = bg })

    local left = tiles:add(1, 1, { pill })
    local right = tiles:add(1, 1, { pill }, (width + 1) * Tile.CELL[1], 0)

    return { { left:chunks(1)[1], { props.text, group }, right:chunks(1)[1] } }
  end,
}

local Object = require('core.Object')
local Tile = require('ui.pixel.Tile')
local paint = require('ui.pixel.paint')

local Tiles = Object:extend()

function Tiles:constructor()
  return {
    pixels = Tile.available() == true,
    list = {},
  }
end

function Tiles:add(cols, rows, commands, ox, oy)
  if not self.pixels then return nil end

  local tile = Tile.acquire(cols, rows)

  tile:paint(function(bitmap)
    paint.run(bitmap, commands, ox, oy)
  end)

  self.list[#self.list + 1] = tile

  return tile
end

function Tiles:count()
  return #self.list
end

function Tiles:release()
  for _, tile in ipairs(self.list) do
    tile:release()
  end

  self.list = {}
end

return Tiles

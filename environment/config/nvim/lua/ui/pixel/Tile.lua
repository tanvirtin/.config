local graphics = require('core.graphics')
local highlight = require('core.highlight')
local Bitmap = require('ui.pixel.Bitmap')

local Tile = {}

Tile.__index = Tile

Tile.CELL = { 16, 32 }
Tile.GROUP = 'UiPixelTile'
Tile.MAX_CELLS = graphics.MAX_CELLS

local free = {}
local epoch = 0

highlight.on_colorscheme('ui.pixel.Tile', function()
  epoch = epoch + 1
end)

function Tile.available()
  return graphics.supported()
end

function Tile.new(cols, rows)
  local id = graphics.id()

  return setmetatable({
    id = id,
    cols = cols,
    rows = rows,
    group = Tile.GROUP .. id,
    bitmap = Bitmap.new(cols * Tile.CELL[1], rows * Tile.CELL[2]),
    lines = graphics.cells(cols, rows),
    sent = nil,
  }, Tile)
end

function Tile:chunks(row, cols)
  if self.defined ~= epoch then
    highlight.set(self.group, { fg = self.id, blend = 0 })
    self.defined = epoch
  end

  local line = self.lines[row or 1]

  if cols and cols < self.cols then line = line:sub(1, #line / self.cols * cols) end

  return { { line, self.group } }
end

function Tile:paint(draw)
  local bitmap = self.bitmap

  bitmap:clear()
  draw(bitmap)

  local bytes = bitmap:crop(0, 0, bitmap.width - 1, bitmap.height - 1)

  if bytes == self.sent then return self end

  self.sent = bytes
  graphics.upload(self.id, bytes, bitmap.width, bitmap.height, self.cols, self.rows)

  return self
end

function Tile:destroy()
  if self.sent then graphics.delete(self.id) end

  self.sent = nil
end

function Tile.acquire(cols, rows)
  local list = free[cols .. 'x' .. rows]
  local tile = list and table.remove(list)

  if tile then
    tile.pooled = nil

    return tile
  end

  return Tile.new(cols, rows)
end

function Tile:release()
  if self.pooled then return self end

  self:destroy()
  self.pooled = true

  local key = self.cols .. 'x' .. self.rows

  free[key] = free[key] or {}
  table.insert(free[key], self)

  return self
end

function Tile.drain()
  free = {}
end

return Tile

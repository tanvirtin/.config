local graphics = require('core.editor.graphics')
local highlight = require('core.editor.highlight')
local Bitmap = require('ui.pixel.Bitmap')

local Tile = {}

Tile.__index = Tile

Tile.CELL = { 16, 32 }
Tile.GROUP = 'UiPixelTile'
Tile.MAX_CELLS = graphics.MAX_CELLS
Tile.FRAMES = 1024

local free = {}
local epoch = 0
local frames, count, clock, showing = {}, 0, 0, {}

highlight.on_colorscheme('ui.pixel.Tile', function()
  epoch = epoch + 1
end)

local function forget(key)
  local frame = frames[key]

  frames[key] = nil
  count = count - 1
  graphics.delete(frame.id)
end

local function evict()
  local oldest, key

  for k, frame in pairs(frames) do
    if not showing[frame.id] and (not oldest or frame.used < oldest.used) then
      oldest, key = frame, k
    end
  end

  if key then forget(key) end
end

local function image(key, bytes, width, height, cols, rows)
  local frame = frames[key]

  if not frame then
    if count >= Tile.FRAMES then evict() end

    frame = { id = graphics.id() }
    frames[key] = frame
    count = count + 1
    graphics.upload(frame.id, bytes, width, height, cols, rows)
  end

  clock = clock + 1
  frame.used = clock

  return frame.id
end

function Tile.available()
  return graphics.supported()
end

function Tile.frames()
  return count
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

function Tile:show(id)
  if self.shown ~= id then
    local held = self.shown and showing[self.shown]

    if held then showing[self.shown] = held > 1 and held - 1 or nil end
    if id then showing[id] = (showing[id] or 0) + 1 end
  end

  highlight.set(self.group, { fg = id or self.id, blend = 0 })
  self.shown, self.defined = id, epoch
end

function Tile:chunks(row, cols)
  if self.defined ~= epoch then self:show(self.shown) end

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

  self.sent, self.key = bytes, self.cols .. 'x' .. self.rows .. ':' .. bytes
  self.painted = (self.painted or 0) + 1
  self:show(image(self.key, bytes, bitmap.width, bitmap.height, self.cols, self.rows))

  return self
end

function Tile:destroy()
  local id = self.shown

  if id then self:show(nil) end
  if id and self.painted == 1 and not showing[id] and frames[self.key] then forget(self.key) end

  self.sent, self.key, self.painted, self.defined = nil, nil, nil, nil
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
  frames, count, clock, showing = {}, 0, 0, {}
end

return Tile

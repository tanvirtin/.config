local Window = require('core.editor.Window')
local roles = require('ui.pixel.roles')
local Bitmap = require('ui.pixel.Bitmap')
local graphics = require('core.editor.graphics')

local Layer = {}

Layer.__index = Layer

Layer.CELL = { 8, 16 }
Layer.Z = { behind = -1, front = 50 }

function Layer.available()
  return graphics.supported()
end

function Layer.new(opts)
  local cols, rows = Window.screen_width(), Window.screen_height()

  return setmetatable({
    cols = cols,
    rows = rows,
    bitmap = Bitmap.new(cols * Layer.CELL[1], rows * Layer.CELL[2]),
    ids = { graphics.id(), graphics.id() },
    turn = 1,
    z = opts and opts.front and Layer.Z.front or Layer.Z.behind,
    shown = nil,
    colors = {},
  }, Layer)
end

function Layer:color(name)
  local key = tostring(name)

  if not self.colors[key] then self.colors[key] = roles.rgb(name) end

  return self.colors[key]
end

function Layer:point(x, y)
  return x * Layer.CELL[1], y * Layer.CELL[2]
end

function Layer:begin()
  self.bitmap:clear()

  return self
end

function Layer:flush()
  local bitmap = self.bitmap

  if not bitmap:dirty() then
    if self.shown then graphics.delete(self.shown) end

    self.shown = nil

    return self
  end

  local cell_w, cell_h = Layer.CELL[1], Layer.CELL[2]
  local left, top, right, bottom = bitmap:bounds()
  local col, row = math.floor(left / cell_w), math.floor(top / cell_h)
  local last_col, last_row = math.floor(right / cell_w), math.floor(bottom / cell_h)
  local bytes, width, height =
    bitmap:crop(col * cell_w, row * cell_h, (last_col + 1) * cell_w - 1, (last_row + 1) * cell_h - 1)
  local id = self.ids[self.turn]

  graphics.draw(id, bytes, width, height, {
    row = row + 1,
    col = col + 1,
    cols = last_col - col + 1,
    rows = last_row - row + 1,
    z = self.z,
  }, self.shown)

  self.shown = id
  self.turn = 3 - self.turn

  return self
end

function Layer:destroy()
  if self.shown then graphics.delete(self.shown) end

  self.shown = nil
end

return Layer

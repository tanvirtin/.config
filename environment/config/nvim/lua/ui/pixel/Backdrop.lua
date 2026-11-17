local event = require('core.event')
local Timer = require('core.Timer')
local Object = require('core.Object')
local Window = require('core.Window')
local Bitmap = require('ui.pixel.Bitmap')
local graphics = require('core.graphics')

local Backdrop = Object:extend()

Backdrop.CELL = { 8, 16 }
Backdrop.Z = -1500000000

local registry = {}
local serial = 0
local listening = false
local queued = false

local function no_key()
  return ''
end

local function schedule()
  if queued then return end

  queued = true

  Timer.schedule(function()
    queued = false
    Backdrop.refresh_all()
  end)
end

local function invalidate_all()
  for _, backdrop in pairs(registry) do
    backdrop:invalidate()
  end

  schedule()
end

local function listen()
  if listening then return end

  listening = true

  local group = event.augroup('ui.pixel.Backdrop')

  group.on({
    'WinScrolled',
    'WinResized',
    'VimResized',
    'WinNew',
    'WinClosed',
    'TabEnter',
    'WinEnter',
    'WinLeave',
    'FocusGained',
    'FocusLost',
  }, schedule)
  group.on('ColorScheme', invalidate_all)
end

local function overlap(rect, cover)
  local left, top = math.max(rect.col, cover.col), math.max(rect.row, cover.row)
  local right = math.min(rect.col + rect.width, cover.col + cover.width)
  local bottom = math.min(rect.row + rect.height, cover.row + cover.height)

  if right <= left or bottom <= top then return nil end

  return { col = left - rect.col, row = top - rect.row, width = right - left, height = bottom - top }
end

local function signature_of(rect, covers, content, key)
  local parts = { rect.row, rect.col, rect.width, rect.height, content, key }

  for _, cover in ipairs(covers) do
    parts[#parts + 1] = string.format('%d,%d,%d,%d', cover.row, cover.col, cover.width, cover.height)
  end

  return table.concat(parts, ';')
end

local function visible_pixels(bitmap)
  if not bitmap:dirty() then return false end

  local left, top, right, bottom = bitmap:bounds()

  for y = top, bottom do
    for x = left, right do
      if select(4, bitmap:pixel(x, y)) > 0 then return true end
    end
  end

  return false
end

function Backdrop:constructor(options)
  serial = serial + 1
  listen()

  local backdrop = {
    serial = serial,
    window = options.window,
    draw = options.draw,
    key = options.key or no_key,
    ids = { graphics.id(), graphics.id() },
    turn = 1,
    shown = nil,
    bitmap = nil,
    signature = nil,
    content = 0,
  }

  registry[serial] = backdrop

  return backdrop
end

function Backdrop:covers()
  local zindex = self.window:get_zindex()
  local covers = {}

  for _, other in ipairs(Window.list_tab()) do
    if other.win_id ~= self.window.win_id and other:is_visible() then
      local other_zindex = other:get_zindex()

      if other_zindex > 0 and other_zindex > zindex then covers[#covers + 1] = other:get_screen_rect() end
    end
  end

  return covers
end

function Backdrop:release()
  if self.shown then graphics.delete(self.shown) end

  self.shown = nil

  return self
end

function Backdrop:paint(rect, covers)
  local cols, rows = rect.width, rect.height

  if cols < 1 or rows < 1 then return self:release() end

  local cell_w, cell_h = Backdrop.CELL[1], Backdrop.CELL[2]
  local width, height = cols * cell_w, rows * cell_h

  if not self.bitmap or self.bitmap.width ~= width or self.bitmap.height ~= height then
    self.bitmap = Bitmap.new(width, height)
  end

  local bitmap = self.bitmap

  bitmap:clear()
  self.draw(bitmap, { cols = cols, rows = rows, width = width, height = height, cell = Backdrop.CELL })

  for _, cover in ipairs(covers) do
    local box = overlap(rect, cover)

    if box then bitmap:erase(box.col * cell_w, box.row * cell_h, box.width * cell_w, box.height * cell_h) end
  end

  if not visible_pixels(bitmap) then return self:release() end

  local bytes = bitmap:crop(0, 0, width - 1, height - 1)
  local id = self.ids[self.turn]

  graphics.draw(id, bytes, width, height, {
    row = rect.row + 1,
    col = rect.col + 1,
    cols = cols,
    rows = rows,
    z = Backdrop.Z,
  }, self.shown)

  self.shown = id
  self.turn = 3 - self.turn

  return self
end

function Backdrop:refresh()
  if not self.window:is_valid() then return self:destroy() end
  if not self.window:is_visible() then return self:hide() end
  if not Backdrop.available() then return self end

  local rect = self.window:get_screen_rect()
  local covers = self:covers()
  local signature = signature_of(rect, covers, self.content, self.key())

  if signature ~= self.signature then
    self.signature = signature
    self:paint(rect, covers)
  end

  return self
end

function Backdrop:invalidate()
  self.content = self.content + 1

  return self
end

function Backdrop:hide()
  self:release()
  self.signature = nil

  return self
end

function Backdrop:destroy()
  self:hide()
  registry[self.serial] = nil

  return self
end

function Backdrop.available()
  return graphics.supported()
end

function Backdrop.count()
  local total = 0

  for _ in pairs(registry) do
    total = total + 1
  end

  return total
end

function Backdrop.refresh_all()
  local live = {}

  for _, backdrop in pairs(registry) do
    live[#live + 1] = backdrop
  end

  for _, backdrop in ipairs(live) do
    backdrop:refresh()
  end
end

return Backdrop

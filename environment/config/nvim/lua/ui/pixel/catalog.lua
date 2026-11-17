local text = require('core.text')
local Timer = require('core.Timer')
local Tile = require('ui.pixel.Tile')
local paint = require('ui.pixel.paint')
local Tiles = require('ui.pixel.Tiles')
local Animation = require('ui.pixel.Animation')

local max = math.max

local catalog = {}

local PREFIX = 'ui.pixel.components.'

catalog.NAMES = { 'bar', 'ring', 'sparkline', 'badge', 'card', 'loader' }

local function sorted_keys(map)
  local keys = {}

  for key in pairs(map) do
    keys[#keys + 1] = key
  end

  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  return keys
end

local function unknown(name)
  error(string.format('unknown component %s (%s)', tostring(name), table.concat(catalog.NAMES, ', ')), 0)
end

function catalog.get(name)
  if type(name) ~= 'string' then unknown(name) end

  local path = PREFIX .. name
  local ok, component = pcall(require, path)

  if ok then return component end
  if tostring(component):find('module \'' .. path .. '\' not found', 1, true) then unknown(name) end

  error(component, 0)
end

function catalog.resolve(name, props)
  local component = catalog.get(name)
  local allowed = component.props
  local given = props or {}

  for _, key in ipairs(sorted_keys(given)) do
    local spec = allowed[key]

    if not spec then
      error(string.format('%s has no prop %s (%s)', name, tostring(key), table.concat(sorted_keys(allowed), ', ')), 0)
    end

    if type(given[key]) ~= spec[1] then
      error(string.format('%s.%s must be a %s, got %s', name, key, spec[1], type(given[key])), 0)
    end
  end

  local resolved = {}

  for key, spec in pairs(allowed) do
    resolved[key] = spec[2]
  end

  for key, value in pairs(given) do
    resolved[key] = value
  end

  return resolved
end

function catalog.animation(name, props)
  local component = catalog.get(name)

  if component.render and not component.commands then
    error(string.format('%s has no animation, use catalog.render', name), 0)
  end

  local resolved = catalog.resolve(name, props)
  local cols, rows = component.size(resolved)
  local animation

  animation = Animation({
    cols = cols,
    rows = rows,
    draw = function(bitmap, now)
      paint.run(bitmap, component.commands(animation.props, bitmap.width, bitmap.height, now))
    end,
  })
  animation.props = resolved

  animation.set = function(self, next)
    local next_props = catalog.resolve(name, next)
    local next_cols, next_rows = component.size(next_props)

    if next_cols ~= self.cols or next_rows ~= self.rows then
      self:stop()
      self.cols, self.rows = next_cols, next_rows
    end

    self.props = next_props

    return self
  end

  return animation
end

local function row_width(row)
  local parts = {}

  for _, chunk in ipairs(row) do
    parts[#parts + 1] = chunk[1]
  end

  return text.width(table.concat(parts))
end

function catalog.size_of(name, props)
  local component = catalog.get(name)
  local resolved = catalog.resolve(name, props)

  if not component.render then return component.size(resolved) end

  local rows = component.render(resolved, { pixels = false })
  local cols = 0

  for _, row in ipairs(rows) do
    cols = max(cols, row_width(row))
  end

  return cols, #rows
end

function catalog.render(name, props)
  local component = catalog.get(name)
  local resolved = catalog.resolve(name, props)
  local tiles = Tiles()
  local lines = {}

  if component.render then
    lines = component.render(resolved, tiles)
  elseif tiles.pixels then
    local cols, rows = component.size(resolved)
    local tile =
      tiles:add(cols, rows, component.commands(resolved, cols * Tile.CELL[1], rows * Tile.CELL[2], Timer.now()))

    for row = 1, rows do
      lines[row] = tile:chunks(row)
    end
  else
    lines = component.fallback and component.fallback(resolved) or {}
  end

  return {
    lines = lines,
    release = function()
      tiles:release()
    end,
  }
end

function catalog.describe()
  local lines = {}

  for _, name in ipairs(catalog.NAMES) do
    local props = catalog.get(name).props
    local parts = {}

    for _, key in ipairs(sorted_keys(props)) do
      parts[#parts + 1] = string.format('%s %s=%s', key, props[key][1], tostring(props[key][2]))
    end

    lines[#lines + 1] = name .. ': ' .. table.concat(parts, ', ')
  end

  return lines
end

return catalog

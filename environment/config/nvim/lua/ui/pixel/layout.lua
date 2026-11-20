local text = require('core.text')

local layout = {}

local DIRECTIONS = { row = 'x', column = 'y' }
local OTHER = { x = 'y', y = 'x' }
local ALIGN = {
  x = { left = 0, center = 1, right = 2 },
  y = { top = 0, center = 1, bottom = 2 },
}

local function fail(message)
  error('layout: ' .. message, 0)
end

local function check_count(value, name)
  if type(value) ~= 'number' or value < 0 or value % 1 ~= 0 then
    fail(name .. ' must be a whole number of cells, got ' .. tostring(value))
  end
  return value
end

local function optional_count(value, name)
  if value == nil then return nil end
  return check_count(value, name)
end

local function parse_direction(value)
  local axis = DIRECTIONS[value or 'row']
  if not axis then fail('invalid direction ' .. tostring(value)) end
  return axis
end

local function parse_padding(padding)
  if type(padding) ~= 'table' then
    local all = padding == nil and 0 or check_count(padding, 'padding')
    return { x = { all, all }, y = { all, all } }
  end

  return {
    x = { check_count(padding.left or 0, 'padding.left'), check_count(padding.right or 0, 'padding.right') },
    y = { check_count(padding.top or 0, 'padding.top'), check_count(padding.bottom or 0, 'padding.bottom') },
  }
end

local function parse_sizing(value, name)
  if value == nil or value == 'fit' then return { kind = 'fit' } end
  if value == 'grow' then return { kind = 'grow' } end
  if type(value) == 'number' then return { kind = 'fixed', value = check_count(value, name) } end

  local percent = type(value) == 'string' and tonumber(value:match('^(%d+%.?%d*)%%$'))
  if percent then return { kind = 'percent', value = percent } end

  fail('invalid ' .. name .. ' ' .. tostring(value))
end

local function align_mode(axis, value)
  local mode = ALIGN[axis][value]
  if mode == nil then fail('invalid align.' .. axis .. ' ' .. tostring(value)) end
  return mode
end

local function parse_align(align)
  local spec = align or {}
  return { x = align_mode('x', spec.x or 'left'), y = align_mode('y', spec.y or 'top') }
end

local function clamp(rec, axis, value)
  local low, high = rec.min[axis] or 0, rec.max[axis]
  local bounded = math.max(value, low)

  if high then return math.min(bounded, high) end
  return bounded
end

local function contribution(rec, axis)
  local sizing = rec.size[axis]
  if sizing.kind == 'fit' then return rec.fit[axis] end
  if sizing.kind == 'fixed' then return clamp(rec, axis, sizing.value) end
  return clamp(rec, axis, 0)
end

local function content_size(rec, axis)
  if rec.text then return axis == 'x' and text.width(rec.text) or 1 end

  local total = 0
  for _, child in ipairs(rec.children) do
    local size = contribution(child, axis)
    if axis == rec.direction then
      total = total + size
    else
      total = math.max(total, size)
    end
  end

  if axis == rec.direction then total = total + rec.gap * math.max(#rec.children - 1, 0) end
  return total
end

local function fit_size(rec, axis)
  local pad = rec.pad[axis]
  return clamp(rec, axis, pad[1] + pad[2] + content_size(rec, axis))
end

local function size_for(rec, axis, available)
  local sizing = rec.size[axis]
  if sizing.kind == 'fixed' then return clamp(rec, axis, sizing.value) end
  if sizing.kind == 'fit' then return rec.fit[axis] end
  if sizing.kind == 'grow' then return clamp(rec, axis, available) end
  return clamp(rec, axis, math.floor(available * sizing.value / 100))
end

local function share(sizes, growers, space)
  if #growers == 0 then return end

  local each = math.floor(space / #growers)
  local extra = space - each * #growers
  for k, i in ipairs(growers) do
    sizes[i] = each + (k <= extra and 1 or 0)
  end
end

local function largest_shrinkable(rec, axis, sizes)
  local pick

  for i, child in ipairs(rec.children) do
    local kind = child.size[axis].kind
    local shrinkable = kind == 'fit' or kind == 'grow'
    local room = sizes[i] > clamp(child, axis, 0)

    if shrinkable and room and (not pick or sizes[i] > sizes[pick]) then pick = i end
  end

  return pick
end

local function shrink(rec, axis, sizes, overflow)
  for _ = 1, overflow do
    local pick = largest_shrinkable(rec, axis, sizes)
    if not pick then return end
    sizes[pick] = sizes[pick] - 1
  end
end

local function main_sizes(rec, axis, inner)
  local sizes, growers = {}, {}
  local used = rec.gap * math.max(#rec.children - 1, 0)

  for i, child in ipairs(rec.children) do
    if child.size[axis].kind == 'grow' then
      sizes[i] = 0
      growers[#growers + 1] = i
    else
      sizes[i] = size_for(child, axis, inner)
      used = used + sizes[i]
    end
  end

  local leftover = inner - used
  if leftover >= 0 then
    share(sizes, growers, leftover)
  else
    shrink(rec, axis, sizes, -leftover)
  end

  for i, child in ipairs(rec.children) do
    sizes[i] = clamp(child, axis, sizes[i])
  end
  return sizes
end

local function child_sizes(rec, inner)
  local main = rec.direction
  local cross = OTHER[main]
  local along = main_sizes(rec, main, inner[main])
  local sizes = {}

  for i, child in ipairs(rec.children) do
    sizes[i] = { [main] = along[i], [cross] = size_for(child, cross, inner[cross]) }
  end
  return sizes
end

local function run_length(rec, sizes, axis)
  local total = rec.gap * math.max(#sizes - 1, 0)
  for _, size in ipairs(sizes) do
    total = total + size[axis]
  end
  return total
end

local function has_grow(rec, axis)
  for _, child in ipairs(rec.children) do
    if child.size[axis].kind == 'grow' then return true end
  end
  return false
end

local function offset(spare, mode)
  return math.floor(spare * mode / 2)
end

local function child_origins(rec, origin, sizes, inner)
  local main = rec.direction
  local cross = OTHER[main]
  local spare = math.max(inner[main] - run_length(rec, sizes, main), 0)
  local run = has_grow(rec, main) and 0 or offset(spare, rec.align[main])
  local cursor = origin[main] + rec.pad[main][1] + run
  local origins = {}

  for i, size in ipairs(sizes) do
    local at = { [main] = cursor }
    local cross_spare = math.max(inner[cross] - size[cross], 0)
    at[cross] = origin[cross] + rec.pad[cross][1] + offset(cross_spare, rec.align[cross])
    origins[i] = at
    cursor = cursor + size[main] + rec.gap
  end
  return origins
end

local function place(rec, origin, size, depth, boxes)
  boxes[#boxes + 1] = {
    node = rec.node,
    id = rec.node.id,
    x = origin.x,
    y = origin.y,
    w = size.x,
    h = size.y,
    depth = depth,
  }

  local inner = {
    x = size.x - rec.pad.x[1] - rec.pad.x[2],
    y = size.y - rec.pad.y[1] - rec.pad.y[2],
  }
  local sizes = child_sizes(rec, inner)
  local origins = child_origins(rec, origin, sizes, inner)

  for i, child in ipairs(rec.children) do
    place(child, origins[i], sizes[i], depth + 1, boxes)
  end
end

local function record(node)
  if type(node) ~= 'table' then fail('node must be a table, got ' .. type(node)) end
  if node.text ~= nil and type(node.text) ~= 'string' then fail('text must be a string') end

  local children = node.children or {}
  if node.text and #children > 0 then fail('a text node cannot have children') end

  local rec = {
    node = node,
    text = node.text,
    direction = parse_direction(node.direction),
    gap = check_count(node.gap or 0, 'gap'),
    pad = parse_padding(node.padding),
    size = { x = parse_sizing(node.width, 'width'), y = parse_sizing(node.height, 'height') },
    min = { x = optional_count(node.min_width, 'min_width'), y = optional_count(node.min_height, 'min_height') },
    max = { x = optional_count(node.max_width, 'max_width'), y = optional_count(node.max_height, 'max_height') },
    align = parse_align(node.align),
    children = {},
  }

  for i, child in ipairs(children) do
    rec.children[i] = record(child)
  end

  rec.fit = { x = fit_size(rec, 'x'), y = fit_size(rec, 'y') }
  return rec
end

function layout.compute(root, width, height)
  local rec = record(root)
  local size = {
    x = size_for(rec, 'x', check_count(width, 'width')),
    y = size_for(rec, 'y', check_count(height, 'height')),
  }
  local boxes = {}

  place(rec, { x = 0, y = 0 }, size, 0, boxes)
  return boxes
end

return layout

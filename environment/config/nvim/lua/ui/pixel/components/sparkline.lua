local markup = require('ui.markup')
local roles = require('ui.pixel.roles')

local floor, min, max = math.floor, math.min, math.max
local LEVELS = { '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' }

local INSET = 3
local LINE_THICKNESS = 2
local FILL_ALPHA = 0.18
local DOT_RADIUS = 2.5

local sparkline = {
  name = 'sparkline',
  props = {
    values = { 'table', {} },
    cols = { 'number', 8 },
    color = { 'string', 'accent' },
    fill = { 'boolean', true },
    dot = { 'boolean', true },
  },
}

local function numbers(values)
  local out = {}

  for _, value in ipairs(values) do
    if type(value) == 'number' then out[#out + 1] = value end
  end

  return out
end

local function plot(values, plot_w, plot_h)
  local lo, hi = values[1], values[1]

  for _, value in ipairs(values) do
    lo, hi = min(lo, value), max(hi, value)
  end

  local count, points = #values, {}

  for i, value in ipairs(values) do
    local x = count == 1 and plot_w / 2 or (i - 1) / (count - 1) * plot_w
    local y = hi == lo and plot_h / 2 or plot_h - (value - lo) / (hi - lo) * plot_h
    points[i] = { x = INSET + x, y = INSET + y }
  end

  return points
end

local function height_at(points, x, plot_w)
  local count = #points

  if count == 1 then return points[1].y end

  local t = (x - INSET) / plot_w * (count - 1)
  local i = min(max(floor(t), 0), count - 2)
  local a, b = points[i + 1], points[i + 2]

  return a.y + (b.y - a.y) * (t - i)
end

function sparkline.size(props)
  return props.cols, 1
end

function sparkline.fallback(props)
  local values = numbers(props.values)
  local cols = props.cols
  local group = markup.group(props.color)

  if #values == 0 then return { { { (' '):rep(cols) } } } end

  local lo, hi, shown = math.huge, -math.huge, {}

  for i = max(1, #values - cols + 1), #values do
    shown[#shown + 1] = values[i]
    lo, hi = min(lo, values[i]), max(hi, values[i])
  end

  local glyphs = {}

  for _, value in ipairs(shown) do
    local level = hi == lo and 4 or floor((value - lo) / (hi - lo) * 7 + 0.5) + 1

    glyphs[#glyphs + 1] = LEVELS[level]
  end

  local row = {}
  local blank = cols - #glyphs

  if blank > 0 then row[#row + 1] = { (' '):rep(blank) } end

  row[#row + 1] = { table.concat(glyphs), group }

  return { row }
end

function sparkline.animated()
  return false
end

function sparkline.commands(props, width, height)
  local values = numbers(props.values)

  if #values == 0 then return {} end

  local plot_w, plot_h = width - 2 * INSET, height - 2 * INSET
  local points = plot(values, plot_w, plot_h)
  local rgb = roles.rgb(props.color)
  local bottom = INSET + plot_h
  local last = points[#points]

  return {
    {
      kind = 'custom',
      x = 0,
      y = 0,
      w = width,
      h = height,
      draw = function(bitmap)
        if props.fill then
          for px = INSET, INSET + plot_w - 1 do
            local y = height_at(points, px + 0.5, plot_w)

            if bottom > y then bitmap:rect(px, y, 1, bottom - y, rgb, FILL_ALPHA) end
          end
        end

        for i = 1, #points - 1 do
          local a, b = points[i], points[i + 1]

          bitmap:line(a.x, a.y, b.x, b.y, LINE_THICKNESS, rgb, 1)
        end

        if props.dot then bitmap:disc(last.x, last.y, DOT_RADIUS, rgb, 1) end
      end,
    },
  }
end

return sparkline

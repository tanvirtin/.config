local roles = require('ui.pixel.roles')

local surface = {}

surface.RADIUS = 10
surface.ELEVATION = {
  surface = { fill = 'UiSurface', border = 'UiBorder', shadow = 0 },
  raised = { fill = 'UiSurfaceRaised', border = 'UiBorder', shadow = 0.22 },
  modal = { fill = 'UiSurfaceRaised', border = 'UiAccent', shadow = 0.32 },
}
surface.GROUP = 'UiBackdropNormal'

local REMAPPED = { Normal = true, NormalFloat = true, FloatBorder = true, EndOfBuffer = true }
local BORDER_WIDTH = 1.5
local BORDER_ALPHA = 0.9
local SHADOW_OFFSET = 2
local SHADOW_LAYERS = 3

function surface.resolve(spec)
  if spec == true or spec == nil then spec = {} end

  local name = spec.elevation or 'surface'
  local elevation = surface.ELEVATION[name]

  if not elevation then error(string.format('unknown elevation %s (surface, raised, modal)', name)) end

  local border = spec.border

  if border == nil or border == true then
    border = elevation.border
  elseif border == false then
    border = false
  end

  return {
    elevation = name,
    fill = elevation.fill,
    border = border,
    shadow = elevation.shadow,
    radius = spec.radius or surface.RADIUS,
  }
end

function surface.draw(bitmap, size, spec)
  local x, y = 2, 2
  local width, height = size.width - 4, size.height - 4
  local radius = spec.radius

  if spec.shadow > 0 then
    for k = 0, SHADOW_LAYERS - 1 do
      bitmap:rect(
        x - k,
        y + SHADOW_OFFSET - k,
        width + 2 * k,
        height + 2 * k,
        { 0, 0, 0 },
        spec.shadow / SHADOW_LAYERS,
        radius + k
      )
    end
  end

  bitmap:rect(x, y, width, height, roles.rgb(roles.background(spec.fill)), 1, radius)

  if spec.border then bitmap:border(x, y, width, height, BORDER_WIDTH, roles.rgb(spec.border), BORDER_ALPHA, radius) end

  return bitmap
end

function surface.window_border()
  return { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' }
end

function surface.winhl(existing)
  local entries, has_normal = {}, false

  if existing and existing ~= '' then
    for pair in existing:gmatch('[^,]+') do
      local from = pair:match('^([^:]+)')

      if REMAPPED[from] then pair = from .. ':' .. surface.GROUP end

      entries[#entries + 1] = pair
      has_normal = has_normal or from == 'Normal'
    end
  end

  if not has_normal then table.insert(entries, 1, 'Normal:' .. surface.GROUP) end

  return table.concat(entries, ',')
end

return surface

local motion = require('ui.motion')
local markup = require('ui.markup')
local roles = require('ui.pixel.roles')

local min, max, floor = math.min, math.max, math.floor
local GLYPHS = { '○', '◔', '◑', '◕', '●' }

return {
  name = 'ring',
  props = {
    value = { 'number', 0 },
    color = { 'string', 'accent' },
    track = { 'string', 'muted' },
    thickness = { 'number', 3 },
    indeterminate = { 'boolean', false },
    period_ms = { 'number', 900 },
  },
  size = function()
    return 2, 1
  end,
  fallback = function(props)
    local glyph = props.indeterminate and '◌' or GLYPHS[floor(motion.clamp(props.value) * 4 + 0.5) + 1]

    return { { { glyph, markup.group(props.color) }, { ' ' } } }
  end,
  animated = function(props)
    return props.indeterminate
  end,
  commands = function(props, width, height, now)
    return {
      {
        kind = 'custom',
        x = 0,
        y = 0,
        w = width,
        h = height,
        draw = function(bitmap)
          local cx, cy = width / 2, height / 2
          local radius = height / 2 - props.thickness / 2 - 3
          local color = roles.rgb(props.color)

          bitmap:ring(cx, cy, radius, props.thickness, roles.rgb(props.track), 0.3)

          if props.indeterminate then
            local start = now % props.period_ms / props.period_ms

            bitmap:arc(cx, cy, radius, props.thickness, start, start + 0.3, color, 1)
          elseif props.value > 0 then
            bitmap:arc(cx, cy, radius, props.thickness, 0, min(1, max(0, props.value)), color, 1)
          end
        end,
      },
    }
  end,
}

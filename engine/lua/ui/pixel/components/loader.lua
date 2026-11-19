local motion = require('ui.motion')
local markup = require('ui.markup')
local roles = require('ui.pixel.roles')
local indicators = require('ui.pixel.indicators')

local KINDS = { 'thinking', 'waiting', 'loading', 'idle' }

local function check(kind)
  for _, allowed in ipairs(KINDS) do
    if kind == allowed then return end
  end

  error(string.format('unknown loader kind %s (%s)', tostring(kind), table.concat(KINDS, ', ')), 0)
end

local function colour(props)
  if props.color ~= '' then return props.color end

  return indicators.ROLES[props.kind]
end

return {
  name = 'loader',
  props = {
    kind = { 'string', 'loading' },
    color = { 'string', '' },
  },
  size = function(props)
    check(props.kind)

    return 2, 1
  end,
  fallback = function(props)
    check(props.kind)

    return { { { indicators.glyph(props.kind), markup.group(colour(props)) }, { ' ' } } }
  end,
  animated = function(props)
    return props.kind ~= 'idle'
  end,
  commands = function(props, width, height, now)
    local rgb = roles.rgb(colour(props))

    return {
      {
        kind = 'custom',
        x = 0,
        y = 0,
        w = width,
        h = height,
        draw = function(bitmap)
          indicators[props.kind](bitmap, motion.step(now), rgb)
        end,
      },
    }
  end,
}

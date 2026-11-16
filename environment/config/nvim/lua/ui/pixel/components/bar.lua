local motion = require('ui.motion')
local markup = require('ui.markup')
local roles = require('ui.pixel.roles')

local floor = math.floor
local TRACK_HEIGHT = 6
local INSET = 2
local RADIUS = 3
local TRACK_OPACITY = 0.35
local SEGMENT = 0.3

return {
  name = 'bar',
  props = {
    value = { 'number', 0 },
    cols = { 'number', 12 },
    color = { 'string', 'accent' },
    track = { 'string', 'muted' },
    indeterminate = { 'boolean', false },
    period_ms = { 'number', 1400 },
  },
  size = function(props)
    return props.cols, 1
  end,
  fallback = function(props)
    local filled = props.indeterminate and 0 or floor(motion.clamp(props.value) * props.cols + 0.5)
    local row = {}

    if filled > 0 then row[#row + 1] = { ('▰'):rep(filled), markup.group(props.color) } end
    if props.cols > filled then row[#row + 1] = { ('▱'):rep(props.cols - filled), markup.group(props.track) } end

    return { row }
  end,
  animated = function(props)
    return props.indeterminate == true
  end,
  commands = function(props, width, height, now)
    local x, w = INSET, width - 2 * INSET
    local y = (height - TRACK_HEIGHT) / 2
    local commands = {
      {
        kind = 'rectangle',
        x = x,
        y = y,
        w = w,
        h = TRACK_HEIGHT,
        radius = RADIUS,
        color = roles.rgb(props.track),
        opacity = TRACK_OPACITY,
      },
      { kind = 'scissor_start', x = x, y = y, w = w, h = TRACK_HEIGHT },
    }

    if props.indeterminate then
      local segment = SEGMENT * w
      local phase = now % props.period_ms / props.period_ms
      local left = motion.lerp(-segment, w, motion.ease.in_out(phase))

      commands[#commands + 1] = {
        kind = 'rectangle',
        x = x + left,
        y = y,
        w = segment,
        h = TRACK_HEIGHT,
        radius = RADIUS,
        color = roles.rgb(props.color),
      }
    else
      local fill = motion.clamp(props.value) * w

      if fill > 0 then
        commands[#commands + 1] = {
          kind = 'rectangle',
          x = x,
          y = y,
          w = fill,
          h = TRACK_HEIGHT,
          radius = RADIUS,
          color = roles.rgb(props.color),
        }
      end
    end

    commands[#commands + 1] = { kind = 'scissor_end' }

    return commands
  end,
}

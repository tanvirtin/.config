local motion = require('ui.design.motion')

local static = {}

static.FRAME_MS = motion.FRAME_MS
static.AMBIENT_MS = motion.STEP_MS

static.ORDER = { 'whisper', 'light', 'medium', 'heavy' }

static.DENSITY = {
  whisper = 0.3,
  light = 0.45,
  medium = 0.6,
  heavy = 0.85,
}

function static.density(name, fade)
  local density = static.DENSITY[name]

  if not density then
    error(string.format('unknown static preset %s (%s)', tostring(name), table.concat(static.ORDER, ', ')), 2)
  end

  return density * (fade or 1)
end

function static.seed(now, ambient)
  return math.floor((now or 0) / (ambient and static.AMBIENT_MS or static.FRAME_MS))
end

return static

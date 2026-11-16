local indicators = require('ui.pixel.indicators')

local orb = {}

orb.COLS = 2
orb.LINGER_MS = 500
orb.PERIOD_MS = indicators.PERIOD_MS.orb

function orb.live()
  local chunk = indicators.chunk('orb', 'UiThought')

  return chunk and { chunk } or nil
end

function orb.stop()
  indicators.stop()
end

return orb

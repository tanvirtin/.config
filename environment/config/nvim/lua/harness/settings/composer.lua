local Config = require('core.Config')
local tokens = require('ui.design.motion')

return Config({
  height = 10,
  ease_ms = tokens.DURATION.fast,
  reference_lines = 2000,
})

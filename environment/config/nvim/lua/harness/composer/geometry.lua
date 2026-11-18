local Window = require('core.Window')
local settings = require('harness.settings')

local composer_geometry = {}

composer_geometry.WINBAR_ROWS = 1

function composer_geometry.footprint()
  return settings.composer:get('height') + composer_geometry.WINBAR_ROWS + Window.split_rows()
end

return composer_geometry

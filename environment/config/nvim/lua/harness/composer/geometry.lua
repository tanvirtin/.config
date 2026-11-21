local Lens = require('ui.Lens')
local Window = require('core.editor.Window')
local settings = require('harness.settings')

local composer_geometry = {}

composer_geometry.WINBAR_ROWS = 1

composer_geometry.INLINE_HEIGHT = 5

function composer_geometry.footprint()
  return settings.composer:get('height') + composer_geometry.WINBAR_ROWS + Window.split_rows()
end

function composer_geometry.inline_height()
  return math.min(settings.composer:get('height'), composer_geometry.INLINE_HEIGHT)
end

function composer_geometry.inline_fits(window)
  return Lens.fits(window, composer_geometry.inline_height() + Lens.CHROME_ROWS)
end

return composer_geometry

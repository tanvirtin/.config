local Window = require('core.editor.Window')
local highlight = require('core.editor.highlight')
local Float = require('ui.anim.Float')

local Curtain = {}

Curtain.__index = Curtain

Curtain.GROUP = 'UiAnimCurtain'
Curtain.Z = 260

function Curtain.new(spec, track)
  highlight.set(Curtain.GROUP, { bg = spec.color or '#000000' })

  local width, height = Window.screen_width(), Window.screen_height()

  local float = Float.new({ width = width, height = height - 1, z = Curtain.Z, normal = Curtain.GROUP, blend = 100 })

  return setmetatable({ float = float, track = track }, Curtain)
end

function Curtain:duration()
  return self.track:duration()
end

function Curtain:update(ms)
  self.float:set_blend(self.track:at(ms))
end

function Curtain:destroy()
  self.float:close()
end

return Curtain

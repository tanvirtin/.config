local Timer = require('core.Timer')
local console = require('core.console')
local Surface = require('surfaces.Surface')
local spec = require('ui.anim.spec')

local Scene = Surface:extend()

function Scene:constructor(opts)
  local instance = Surface.constructor(self, { kind = 'scene', title = opts.title or 'Scene', owner = opts.owner })

  instance._scene = opts.scene
  instance._closing = false

  return instance
end

function Scene:open()
  self._stage = spec.build(self._scene, {
    on_done = function(err)
      if err then
        console.notify_now(string.format('scene %s stopped: %s', tostring(self.id), tostring(err)), 'warn')
      end

      self:close()
    end,
  })
  self._started = Timer.now()
  self:set_state('ready')
  self._stage:start()

  return self
end

function Scene:is_open()
  return self._stage ~= nil and self._stage:is_running()
end

function Scene:close()
  if self._closing then return end

  self._closing = true

  if self._stage then self._stage:stop() end

  Surface.close(self)
end

function Scene:snapshot()
  local stage = self._stage

  return string.format(
    '%s: scene "%s" [%s]\n%d actors, %d ms%s',
    self.id,
    self.title,
    self.state,
    stage and #stage.actors or 0,
    stage and stage.duration or 0,
    stage and stage.loop and ', looping' or ''
  )
end

return Scene

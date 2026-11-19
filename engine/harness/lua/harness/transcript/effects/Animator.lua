local Timer = require('core.Timer')
local Object = require('core.Object')
local settings = require('harness.settings')

local Animator = Object:extend()

function Animator:constructor(on_error)
  return {
    timer = Timer(),
    animations = {},
    order = {},
    on_error = on_error,
  }
end

function Animator:count()
  return #self.order
end

function Animator:is_running()
  return self.timer:is_active()
end

function Animator:add(key, step)
  if self.animations[key] == nil then self.order[#self.order + 1] = key end

  self.animations[key] = step

  if not self.timer:is_active() then
    self.timer:every(settings.transcript:get('animate_ms'), function()
      self:tick()
    end)
  end

  return self
end

function Animator:cancel(key)
  if self.animations[key] == nil then return end

  self.animations[key] = nil

  for i, name in ipairs(self.order) do
    if name == key then
      table.remove(self.order, i)
      break
    end
  end

  if #self.order == 0 then self.timer:stop() end
end

function Animator:step(now)
  for _, key in ipairs(vim.list_slice(self.order)) do
    local animation = self.animations[key]

    if animation and not animation(now) and self.animations[key] == animation then self:cancel(key) end
  end
end

function Animator:tick()
  local ok, err = pcall(self.step, self, Timer.now())

  if ok then return end

  self.animations, self.order = {}, {}
  self.timer:stop()

  if self.on_error then self.on_error(err) end
end

function Animator:close()
  self.animations, self.order = {}, {}
  self.timer:close()
end

return Animator

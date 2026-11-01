local hl = require('ui.hl')
local motion = require('ui.motion')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local settings = require('harness.settings')

local Fades = Object:extend()

Fades.NAMESPACE = Buffer.namespace('harness.fade')
Fades.PRIORITY = 100
Fades.MAX = 8

function Fades:constructor(buffer)
  return { buffer = buffer, chunks = {} }
end

function Fades:touch(from, to, now, any_size)
  local limit = settings.transcript:get('fade_rows')

  if settings.transcript:get('fade_ms') <= 0 or (not any_size and to - from + 1 > limit) then return false end

  table.insert(self.chunks, { from = from, to = to, started = now })

  while #self.chunks > Fades.MAX do
    table.remove(self.chunks, 1)
  end

  return true
end

function Fades:step(now)
  local ms = settings.transcript:get('fade_ms')
  local alive = {}

  self.buffer:clear_namespace(Fades.NAMESPACE)

  for _, chunk in ipairs(self.chunks) do
    local progress = (now - chunk.started) / ms

    if progress < 1 then
      local index = motion.steps(hl.FADE_STEPS - 1, motion.ease.out_cubic(progress))

      self.buffer:set_extmark(Fades.NAMESPACE, chunk.from, 0, {
        end_row = chunk.to + 1,
        end_col = 0,
        hl_group = 'UiFade' .. index,
        priority = Fades.PRIORITY,
      })
      alive[#alive + 1] = chunk
    end
  end

  self.chunks = alive

  return #alive > 0
end

return Fades

local hl = require('ui.hl')
local motion = require('ui.motion')
local Timer = require('core.Timer')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local settings = require('harness.settings')
local theme = require('harness.transcript.theme')

local Fades = Object:extend()

Fades.NAMESPACE = Buffer.namespace('harness.fade')
Fades.PRIORITY = 100
Fades.MAX = 8

function Fades:constructor(buffer, view)
  return { buffer = buffer, view = view, chunks = {}, high = -1 }
end

function Fades:observe()
  local view = self.view
  local touched = view.document.touched

  if theme.reduced() or not touched or not view.session:running() or view.session:loading() then return false end

  return self:touch(touched.from, touched.to, Timer.now())
end

function Fades:reveal(row)
  if theme.reduced() then return false end

  local document = self.view.document
  local block = document:block_at(row - 1)

  for _, fold in ipairs(block and block.folds or {}) do
    local from, to = block.start + fold[1], block.start + fold[2]

    if row - 1 >= from and row - 1 <= to then return self:touch(from, to, Timer.now(), true) end
  end

  return false
end

function Fades:touch(from, to, now, any_size)
  local limit = settings.transcript:get('fade_rows')

  if settings.transcript:get('fade_ms') <= 0 or (not any_size and to - from + 1 > limit) then return false end

  if not any_size then
    from = math.max(from, self.high + 1)

    if from > to then return false end
  end

  self.high = math.max(self.high, to)

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

local hl = require('ui.hl')
local tone = require('ui.tone')
local motion = require('ui.motion')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local MarkSpec = require('ui.MarkSpec')
local settings = require('harness.settings')
local theme = require('harness.transcript.theme')
local Block = require('harness.transcript.Block')

local Flashes = Object:extend()

Flashes.NAMESPACE = Buffer.namespace('harness.flash')
Flashes.PRIORITY = MarkSpec.PRIORITY + 50
Flashes.LOOKBACK = 48

function Flashes:constructor(buffer)
  return { buffer = buffer, active = {} }
end

function Flashes:scan(blocks, now)
  if theme.reduced() then return false end

  local ms = settings.transcript:get('flash_ms')

  for index = #blocks, math.max(#blocks - Flashes.LOOKBACK + 1, 1), -1 do
    local block = blocks[index]

    if block.kind == Block.KIND.tool and block.id and block.finished and now - block.finished < ms then
      local flash = self.active[block.id] or {}

      flash.row, flash.started = block.start, block.finished
      flash.tone = block.status == Block.STATUS.failed and tone.ERROR or tone.ACCENT
      self.active[block.id] = flash
    end
  end

  return next(self.active) ~= nil
end

function Flashes:step(now)
  local ms = settings.transcript:get('flash_ms')

  for id, flash in pairs(self.active) do
    local progress = ms > 0 and (now - flash.started) / ms or 1

    if progress >= 1 then
      if flash.mark then self.buffer:del_extmark(Flashes.NAMESPACE, flash.mark) end

      self.active[id] = nil
    else
      local index = motion.steps(hl.FLASH_STEPS, motion.ease.out_cubic(progress))

      flash.group = tone.flash(flash.tone, index)
      flash.mark = self.buffer:set_extmark(Flashes.NAMESPACE, flash.row, 0, {
        id = flash.mark,
        line_hl_group = flash.group,
        priority = Flashes.PRIORITY,
      })
    end
  end

  return next(self.active) ~= nil
end

return Flashes

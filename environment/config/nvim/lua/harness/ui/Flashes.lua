local hl = require('ui.hl')
local tone = require('ui.tone')
local motion = require('ui.motion')
local Timer = require('core.Timer')
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

function Flashes:constructor(buffer, view)
  return { buffer = buffer, view = view, active = {} }
end

local function key_of(block)
  if block.kind == Block.KIND.tool then return block.id end
  if block.kind == Block.KIND.stop then return 'stop:' .. block.start end
end

local function failed(block)
  return block.status == Block.STATUS.failed or (block.kind == Block.KIND.stop and block.reason ~= 'end_turn')
end

function Flashes:observe()
  return self:scan(self.view.document.blocks, Timer.now())
end

function Flashes:scan(blocks, now)
  if theme.reduced() then return false end

  local ms = settings.transcript:get('flash_ms')

  for index = #blocks, math.max(#blocks - Flashes.LOOKBACK + 1, 1), -1 do
    local block = blocks[index]

    local key = key_of(block)

    if key and block.finished and now - block.finished < ms then
      local flash = self.active[key] or {}

      flash.row, flash.started = block.start, block.finished
      flash.tone = failed(block) and tone.ERROR or tone.ACCENT
      self.active[key] = flash
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

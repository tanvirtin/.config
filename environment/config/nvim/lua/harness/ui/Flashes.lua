local tone = require('ui.tone')
local glitch = require('ui.glitch')
local Timer = require('core.Timer')
local Buffer = require('core.Buffer')
local Object = require('core.Object')
local MarkSpec = require('ui.MarkSpec')
local settings = require('harness.settings')
local theme = require('harness.transcript.theme')
local Block = require('harness.transcript.Block')

local Flashes = Object:extend()

Flashes.PRIORITY = MarkSpec.PRIORITY + 50
Flashes.LOOKBACK = 48
Flashes.GLITCH = Buffer.namespace('harness.flash.glitch')
Flashes.GLITCH_FRAME_MS = 40
Flashes.GLITCH_DENSITY = 0.5
Flashes.DONE_DENSITY = 0.35
Flashes.STRETCH = 1.6

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

  local ms = settings.transcript:get('flash_ms') * Flashes.STRETCH

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

function Flashes:glitch(flash, progress, now)
  local line = self.buffer:get_lines(flash.row, flash.row + 1)[1] or ''
  local failed = flash.tone == tone.ERROR
  local seed = math.floor(now / Flashes.GLITCH_FRAME_MS)
  local density = (failed and Flashes.GLITCH_DENSITY or Flashes.DONE_DENSITY) * (1 - progress) ^ 2
  local from = #(line:match('^[^%w]*') or '')

  for _, cell in ipairs(glitch.cols(line, density, seed + flash.row, from)) do
    self.buffer:set_extmark(Flashes.GLITCH, flash.row, cell[1], {
      virt_text = { { cell[2], failed and 'UiError' or 'UiAccent' } },
      virt_text_pos = 'overlay',
      priority = Flashes.PRIORITY,
    })
  end
end

function Flashes:step(now)
  local ms = settings.transcript:get('flash_ms') * Flashes.STRETCH

  self.buffer:clear_namespace(Flashes.GLITCH)

  for id, flash in pairs(self.active) do
    local progress = ms > 0 and (now - flash.started) / ms or 1

    if progress >= 1 then
      self.active[id] = nil
    else
      self:glitch(flash, progress, now)
    end
  end

  return next(self.active) ~= nil
end

return Flashes

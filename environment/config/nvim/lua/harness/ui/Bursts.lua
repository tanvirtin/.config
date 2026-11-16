local Timer = require('core.Timer')
local Object = require('core.Object')
local pip = require('harness.transcript.pip')
local theme = require('harness.transcript.theme')
local Block = require('harness.transcript.Block')

local Bursts = Object:extend()

Bursts.LOOKBACK = 48

function Bursts:constructor(view)
  return { view = view, active = {} }
end

function Bursts:observe()
  return self:scan(self.view.document.blocks, Timer.now())
end

function Bursts:scan(blocks, now)
  if theme.reduced() or not pip.available() then return false end

  for index = #blocks, math.max(#blocks - Bursts.LOOKBACK + 1, 1), -1 do
    local block = blocks[index]

    if block.kind == Block.KIND.tool and block.id and block.finished and now - block.finished < pip.BURST_MS then
      self.active[block.id] = block.finished
    end
  end

  return next(self.active) ~= nil
end

function Bursts:step(now)
  local document = self.view.document
  local blocks = document.blocks

  for index = #blocks, math.max(#blocks - Bursts.LOOKBACK + 1, 1), -1 do
    local finished = blocks[index].id and self.active[blocks[index].id]

    if finished and now - finished >= pip.BURST_MS then
      self.active[blocks[index].id] = nil
      document:redecorate(index)
    end
  end

  for id, finished in pairs(self.active) do
    if now - finished >= pip.BURST_MS then self.active[id] = nil end
  end

  return next(self.active) ~= nil
end

return Bursts

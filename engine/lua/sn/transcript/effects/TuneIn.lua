local glitch = require('ui.glitch')
local Timer = require('core.Timer')
local design = require('ui.design')
local Object = require('core.Object')
local layer = require('ui.design.layer')
local Buffer = require('core.editor.Buffer')
local theme = require('sn.transcript.theme')

local TuneIn = Object:extend()

TuneIn.NAMESPACE = Buffer.namespace('sn.tune_in')
TuneIn.MS = design.motion.DURATION.slow
TuneIn.STATIC = 'heavy'
TuneIn.PRIORITY = layer.of('effect')

function TuneIn:constructor(view)
  return { view = view, started = nil }
end

function TuneIn:before(state)
  local view = self.view
  local was = view.document.state.loading
  local first = not self.seen
  local session = view.session

  self.seen = true

  if theme.reduced() or state.loading then return false end

  local opened = first and session ~= nil and #session.history > 0

  if not was and not opened then return false end

  self.started = Timer.now()

  return true
end

function TuneIn:paint(progress, now)
  local buffer = self.view.buffer
  local density = design.static.density(TuneIn.STATIC, (1 - progress) ^ 2)
  local seed = design.static.seed(now)

  for _, window in ipairs(self.view:windows()) do
    local top, bottom = window:get_visible_range()

    for row, line in ipairs(buffer:get_lines(top, bottom)) do
      local at = top + row - 1

      for _, cell in ipairs(glitch.cols(line, density, seed + at)) do
        buffer:set_extmark(TuneIn.NAMESPACE, at, cell[1], {
          virt_text = { { cell[2], 'UiMuted' } },
          virt_text_pos = 'overlay',
          priority = TuneIn.PRIORITY,
        })
      end
    end
  end
end

function TuneIn:step(now)
  local buffer = self.view.buffer

  if not buffer:is_valid() then return false end

  buffer:clear_namespace(TuneIn.NAMESPACE)

  if not self.started then return false end

  local progress = (now - self.started) / TuneIn.MS

  if progress >= 1 then
    self.started = nil

    return false
  end

  self:paint(progress, now)

  return true
end

return TuneIn

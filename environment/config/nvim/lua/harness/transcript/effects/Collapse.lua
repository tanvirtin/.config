local tone = require('ui.tone')
local Timer = require('core.Timer')
local Object = require('core.Object')
local theme = require('harness.transcript.theme')
local permission = require('harness.types.permission')
local status_line = require('harness.transcript.status_line')

local Collapse = Object:extend()

Collapse.REFUSAL_WINDOW_MS = 2000

function Collapse:constructor(view)
  return { view = view, closing = nil }
end

function Collapse:_refused(now)
  local permissions = self.view.session.permissions
  local decisions = permissions and permissions:decisions() or {}
  local last = decisions[#decisions]

  return last ~= nil
    and last.time ~= nil
    and now - last.time < Collapse.REFUSAL_WINDOW_MS
    and not permission.allows(last.kind)
end

function Collapse:before(state)
  local document = self.view.document
  local previous = document.state

  if theme.reduced() or #(previous.asks or {}) == 0 or #state.asks > 0 then return false end

  local now = Timer.now()
  local card = status_line.card_of(status_line.lines(previous, now))

  if #card == 0 then return false end

  self.closing = { lines = card, started = now, tone = self:_refused(now) and tone.ERROR or tone.ACCENT }
  document.state.closing = self.closing

  return true
end

function Collapse:step(now)
  local view, closing = self.view, self.closing
  local running = view.buffer:is_valid() and closing ~= nil and now - closing.started < status_line.closing_ms()

  if not running and closing and view.document.state.closing == closing then view.document.state.closing = nil end
  if view.buffer:is_valid() then view.document:_status() end

  return running
end

return Collapse

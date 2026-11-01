local Timer = require('core.Timer')
local theme = require('harness.transcript.theme')
local permission = require('harness.types.permission')
local status_line = require('harness.transcript.status_line')

local transcript_motion = {}

transcript_motion.REFUSAL_WINDOW_MS = 2000

local function run(view, key, target)
  view.animator:add(key, function(now)
    return view.buffer:is_valid() and target:step(now)
  end)
end

local function ease_in(view, from, to, any_size)
  if view.fades:touch(from, to, Timer.now(), any_size) then run(view, 'fade', view.fades) end
end

local function refused(view, now)
  local decisions = view.session.permissions and view.session.permissions:decisions() or {}
  local last = decisions[#decisions]

  return last ~= nil
    and last.time ~= nil
    and now - last.time < transcript_motion.REFUSAL_WINDOW_MS
    and not permission.allows(last.kind)
end

function transcript_motion.close_card(view, state)
  local document = view.document
  local previous = document.state

  if theme.reduced() or #(previous.asks or {}) == 0 or #state.asks > 0 then return end

  local now = Timer.now()
  local card = status_line.card_of(status_line.lines(previous, now))

  if #card == 0 then return end

  local closing = { lines = card, started = now, tone = refused(view, now) and 'Error' or 'Accent' }
  local ms = status_line.closing_ms()

  document.state.closing = closing
  view.animator:add('collapse', function(at)
    local running = view.buffer:is_valid() and at - closing.started < ms

    if not running and document.state.closing == closing then document.state.closing = nil end
    if view.buffer:is_valid() then document:_status() end

    return running
  end)
end

function transcript_motion.settle(view)
  local touched = view.document.touched

  if not theme.reduced() and touched and view.session:running() and not view.session:loading() then
    ease_in(view, touched.from, touched.to)
  end

  if view.flashes:scan(view.document.blocks, Timer.now()) then run(view, 'flash', view.flashes) end
end

function transcript_motion.reveal(view, row)
  if theme.reduced() then return end

  local block = view.document:block_at(row - 1)

  for _, fold in ipairs(block and block.folds or {}) do
    local from, to = block.start + fold[1], block.start + fold[2]

    if row - 1 >= from and row - 1 <= to then return ease_in(view, from, to, true) end
  end
end

return transcript_motion

local Object = require('core.Object')
local sticky_bottom = require('harness.ui.sticky_bottom')

local Following = Object:extend()

function Following:constructor(reserve)
  return { reserve = reserve, windows = {} }
end

function Following:of(window)
  local state = self.windows[window.win_id]

  if not state then
    state = {}
    self.windows[window.win_id] = state
  end

  return state
end

function Following:follows(window)
  return sticky_bottom.at_end(window) or self:of(window).top == window:get_visible_range()
end

function Following:track(windows)
  for _, window in ipairs(windows) do
    local state, top = self:of(window), window:get_visible_range()

    local at_end = sticky_bottom.at_end(window)

    if state.seen then state.resting = at_end end

    if at_end then
      state.top = top
    elseif state.top ~= top then
      state.top = nil
    end
  end
end

function Following:resync(window)
  local state, now = self:of(window), self.reserve(window)
  local before = state.reserved

  state.reserved = now

  if before and now > 0 and now < before and self:follows(window) then
    sticky_bottom.release(window, before - now, now)
  end
end

function Following:glide(window, with_cursor)
  self:resync(window)
  sticky_bottom.tail(window, with_cursor, self.reserve(window))
end

function Following:land(window, decorate)
  local reserve = self.reserve(window)
  local state = self:of(window)

  sticky_bottom.pin(window, reserve)
  decorate()
  sticky_bottom.pin(window, reserve)
  state.top = window:get_visible_range()
  state.reserved = reserve
  state.seen = true
  state.resting = true
end

function Following:keep_end(windows)
  for _, window in ipairs(windows) do
    if self:follows(window) then self:glide(window, false) end
  end

  self:track(windows)
end

function Following:hold_end(windows)
  for _, window in ipairs(windows) do
    local top = self:of(window).top

    if top then
      local last = window:get_buffer():get_line_count()
      local on_last = window:get_cursor()[1] >= last

      window:set_top(top + 1)
      self:resync(window)
      sticky_bottom.hold(window, self.reserve(window))

      if on_last then window:set_cursor({ last, 0 }) end
    end
  end

  self:track(windows)
end

function Following:arrive(window)
  local resting = self:of(window).resting

  self.windows[window.win_id] = { seen = true }

  return resting
end

function Following:forget(win_id)
  self.windows[win_id] = nil
end

return Following

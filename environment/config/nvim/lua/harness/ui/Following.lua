local Buffer = require('core.Buffer')
local Object = require('core.Object')
local sticky_bottom = require('harness.ui.sticky_bottom')

local Following = Object:extend()

Following.ANCHOR = Buffer.namespace('harness.following')

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
  return self:of(window).away == false
end

function Following.position(window)
  local view = window:get_view()

  return view.topline - 1, view.topfill
end

function Following.above(top, fill, other_top, other_fill)
  return top < other_top or (top == other_top and fill > other_fill)
end

function Following:edge(window)
  local state = self:of(window)
  local row = state.edge and state.buffer:get_extmark_row(Following.ANCHOR, state.edge)

  if not row then return nil end

  local last = state.buffer:get_line_count() - 1

  if row > last then return last, 0, true end

  return row, state.edge_fill, false
end

function Following:settle(window)
  local state = self:of(window)
  local top, fill = Following.position(window)

  state.buffer = window:get_buffer()
  state.edge = state.buffer:set_extmark(Following.ANCHOR, top, 0, { id = state.edge, right_gravity = true })
  state.edge_fill = fill
  state.top, state.fill, state.seen, state.moved = top, fill, { top, fill }, nil
end

function Following:track(windows)
  for _, window in ipairs(windows) do
    local state, height = self:of(window), window:get_height()
    local top, fill = Following.position(window)
    local seen = state.seen
    local up = seen ~= nil and Following.above(top, fill, seen[1], seen[2])
    local still = seen ~= nil and top == seen[1] and fill == seen[2]
    local down = seen ~= nil and not up and not still
    local at_end = sticky_bottom.at_end(window)

    if state.height ~= nil and state.height ~= height then
      state.moved = (height < state.height) ~= up
    elseif not still then
      state.moved = nil
    end

    if not state.moved then
      local edge, edge_fill, lost = self:edge(window)

      if edge then state.away = Following.above(top, fill, edge, edge_fill) end

      if state.away and down and at_end and (lost or not state.seen_end) then state.away = false end

      state.top, state.fill = top, fill
    end

    state.seen, state.seen_end, state.height = { top, fill }, at_end, height
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
  self:of(window).away = false
  self:settle(window)
end

function Following:land(window, decorate)
  local reserve = self.reserve(window)
  local state = self:of(window)

  sticky_bottom.pin(window, reserve)
  decorate()
  sticky_bottom.pin(window, reserve)
  state.height = window:get_height()
  state.reserved = reserve
  state.away = false
  self:settle(window)
end

function Following:keep_end(windows)
  self:track(windows)

  for _, window in ipairs(windows) do
    if self:follows(window) then self:glide(window, false) end
  end

  self:track(windows)
end

function Following.restore(window, top, fill)
  local cursor = window:get_cursor()

  window:set_view({ topline = top + 1, topfill = fill, lnum = top + 1, col = 0 })

  local _, bottom = window:get_visible_range()

  window:set_cursor({ math.max(top + 1, math.min(cursor[1], bottom)), cursor[2] })
end

function Following:hold_end(windows)
  self:track(windows)

  for _, window in ipairs(windows) do
    local state = self:of(window)

    if state.moved then
      local last = window:get_buffer():get_line_count()
      local on_last = window:get_cursor()[1] >= last

      state.moved = nil
      Following.restore(window, state.top, state.fill)

      if self:follows(window) then
        self:resync(window)
        sticky_bottom.hold(window, self.reserve(window))

        if on_last then window:set_cursor({ last, 0 }) end

        self:settle(window)
      end
    end
  end

  self:track(windows)
end

function Following:settled(window)
  return self:of(window).edge ~= nil
end

function Following:arrive(window)
  return self:of(window).away ~= true
end

function Following:forget(win_id)
  local state = self.windows[win_id]

  if state and state.edge and state.buffer and state.buffer:is_valid() then
    state.buffer:del_extmark(Following.ANCHOR, state.edge)
  end

  self.windows[win_id] = nil
end

return Following

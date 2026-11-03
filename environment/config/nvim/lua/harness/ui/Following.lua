local Buffer = require('core.Buffer')
local Object = require('core.Object')
local sticky_bottom = require('harness.ui.sticky_bottom')

-- A window has one intent, and its viewport is a function of it:
--
--   follow  the newest line sits on the edge, `reserve` rows above the bottom
--   hold    the reader's row sits at the top, where they left it
--
-- Nothing is inferred from how far the view moved. `observe` compares the view
-- against the last one we wrote: a difference is the reader's, because every
-- change we make (a scroll, a rewrite, a resize) records the view it left. The
-- intent only changes when the reader does something.
local Following = Object:extend()

Following.ANCHOR = Buffer.namespace('harness.following')

function Following:constructor(reserve)
  return { reserve = reserve, windows = {}, applying = false }
end

function Following:_clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end

  return value
end

-- a window that came to show another buffer starts clean: the old intent and
-- its mark belong to the buffer that was there
function Following:_refresh(state, window)
  local buffer = window:get_buffer()

  if state.bufnr ~= buffer.bufnr then
    if state.anchor and state.buffer and state.buffer:is_valid() then
      state.buffer:del_extmark(Following.ANCHOR, state.anchor)
    end

    state.bufnr = buffer.bufnr
    state.buffer = buffer
    state.mode = nil
    state.anchor = nil
    state.anchor_fill = 0
    state.anchor_skip = 0
    state.applied = nil
    state.lines = nil
  end

  return state
end

function Following:of(window)
  local state = self.windows[window.win_id]

  if not state then
    state = {}
    self.windows[window.win_id] = state
  end

  return self:_refresh(state, window)
end

function Following:follows(window)
  return self:of(window).mode == 'follow'
end

function Following:holds(window)
  return self:of(window).mode == 'hold'
end

function Following:settled(window)
  return self:of(window).applied ~= nil
end

-- a view difference that comes with a different size is the resize's, not a
-- scroll the reader made
function Following:resized(window)
  local state = self:of(window)

  if state.height == nil then return false end

  return state.height ~= window:get_height() or state.width ~= window:get_width()
end

function Following:_anchor(state, view)
  state.anchor = state.buffer:set_extmark(Following.ANCHOR, view.topline - 1, 0, {
    id = state.anchor,
    right_gravity = true,
  })
  state.anchor_fill = view.topfill
  state.anchor_skip = view.skipcol or 0
end

function Following:_unanchor(state)
  if state.anchor and state.buffer and state.buffer:is_valid() then
    state.buffer:del_extmark(Following.ANCHOR, state.anchor)
  end

  state.anchor, state.anchor_fill, state.anchor_skip = nil, 0, 0
end

-- the reader moved later in the buffer: a lower top line, further into a
-- smoothscrolled line, or one filler row less above it
function Following:_later(now, was)
  if now.topline ~= was.topline then return now.topline > was.topline end
  if (now.skipcol or 0) ~= (was.skipcol or 0) then return (now.skipcol or 0) > (was.skipcol or 0) end

  return (now.topfill or 0) < (was.topfill or 0)
end

function Following:_moved(now, was)
  return now.topline ~= was.topline
    or (now.skipcol or 0) ~= (was.skipcol or 0)
    or (now.topfill or 0) ~= (was.topfill or 0)
end

-- the reader reached the end when the last row they could see is the one the
-- buffer ended on at the last view we wrote, even if the stream has appended
-- since, before their scroll was observed
function Following:_reached_end(state, window)
  if sticky_bottom.at_end(window) then return true end

  local known = state.lines

  if not known then return false end

  return select(2, window:get_visible_range()) >= math.min(known, window:get_buffer():get_line_count())
end

-- A difference from the view we last wrote is the reader's. Reaching the end
-- from above turns following back on; anything else holds the new position.
function Following:observe(window)
  if not window:is_valid() then return end

  local state = self:of(window)
  local now = window:get_view()

  if not state.applied then
    state.applied = now
    state.lines = state.buffer:get_line_count()

    if sticky_bottom.at_end(window) then
      state.mode = 'follow'
      self:_unanchor(state)
    else
      state.mode = 'hold'
      self:_anchor(state, now)
    end

    return
  end

  if not self:_moved(now, state.applied) then return end

  if self:_later(now, state.applied) and self:_reached_end(state, window) then
    state.mode = 'follow'
    self:_unanchor(state)
  else
    state.mode = 'hold'
    self:_anchor(state, now)
  end

  state.applied = now
  state.lines = state.buffer:get_line_count()
end

function Following:observe_all(windows)
  for _, window in ipairs(windows) do
    self:observe(window)
  end
end

function Following:_desired_hold(state, window)
  local row = state.anchor and state.buffer:get_extmark_row(Following.ANCHOR, state.anchor)
  local last = state.buffer:get_line_count() - 1

  -- a rewrite can swallow the tail the reader was on; there is no scroll that
  -- reaches past the last line, so the end is the closest true place
  if not row or row > last then return nil end

  local fill, skip = state.anchor_fill, state.anchor_skip
  local view = window:get_view()
  local height = window:get_height()
  local line = window:get_text_height(row, row)

  return {
    topline = row + 1,
    topfill = self:_clamp(fill, 0, math.max(line - 1, 0)),
    skipcol = skip,
    lnum = self:_clamp(view.lnum, row + 1, math.min(last + 1, row + height)),
    col = view.col,
    curswant = view.curswant,
  }
end

-- A resize moves the text to keep the cursor in view. Put it back where it was
-- first, so only the edge can move it, not the resize.
function Following:_restore(state, window)
  local was = state.applied

  if not was then return end

  local view = window:get_view()
  local last = state.buffer:get_line_count()
  local top = math.min(was.topline, last)

  window:set_view({
    topline = top,
    topfill = was.topfill,
    skipcol = was.skipcol,
    lnum = self:_clamp(view.lnum, top, math.min(last, top + window:get_height() - 1)),
    col = view.col,
    curswant = view.curswant,
  })
end

function Following:_same(now, wanted)
  return now.topline == wanted.topline
    and (now.topfill or 0) == (wanted.topfill or 0)
    and (now.skipcol or 0) == (wanted.skipcol or 0)
    and now.lnum == wanted.lnum
    and now.col == wanted.col
end

-- Puts the viewport where the intent says it should be. Always records the view
-- it leaves, so the next observation knows what we did.
function Following:sync(window, opts)
  if not window:is_valid() then return end

  opts = opts or {}

  local state = self:of(window)
  local wanted

  if state.mode == 'hold' then wanted = self:_desired_hold(state, window) end

  self.applying = true

  if wanted then
    if not self:_same(window:get_view(), wanted) then window:set_view(wanted) end
  else
    state.mode = 'follow'

    if self:resized(window) then self:_restore(state, window) end

    sticky_bottom.tail(window, opts.with_cursor, self.reserve(window))
  end

  state.applied = window:get_view()
  state.lines = state.buffer:get_line_count()
  state.height, state.width = window:get_height(), window:get_width()
  self.applying = false
end

function Following:sync_all(windows, cursors)
  for _, window in ipairs(windows) do
    self:sync(window, { with_cursor = cursors and cursors[window.win_id] })
  end
end

function Following:follow(window)
  local state = self:of(window)

  state.mode = 'follow'
  self:_unanchor(state)
  self:sync(window)
end

function Following:hold(window)
  local state = self:of(window)

  state.mode = 'hold'
  self:_anchor(state, window:get_view())
  self:sync(window)
end

function Following:land(window, decorate)
  local state = self:of(window)
  local reserve = self.reserve(window)

  state.mode = 'follow'
  self:_unanchor(state)

  self.applying = true
  sticky_bottom.pin(window, reserve)

  if decorate then decorate() end

  sticky_bottom.pin(window, reserve)
  state.applied = window:get_view()
  state.lines = state.buffer:get_line_count()
  state.height, state.width = window:get_height(), window:get_width()
  self.applying = false
end

function Following:forget(win_id)
  local state = self.windows[win_id]

  if state and state.anchor and state.buffer and state.buffer:is_valid() then
    state.buffer:del_extmark(Following.ANCHOR, state.anchor)
  end

  self.windows[win_id] = nil
end

return Following

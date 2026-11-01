local geometry = require('harness.ui.composer_geometry')

local sticky_bottom = {}

function sticky_bottom.composer_rows()
  return geometry.footprint()
end

function sticky_bottom.margin(window)
  return math.min(sticky_bottom.composer_rows(), math.floor(window:get_height() / 3))
end

function sticky_bottom.at_end(window)
  if not window:is_valid() then return false end

  return select(2, window:get_visible_range()) >= window:get_buffer():get_line_count()
end

function sticky_bottom.room(window)
  local last = window:get_buffer():get_line_count()
  local top = window:get_visible_range()

  return window:get_height() - window:get_text_height(top, last - 1)
end

-- The invariant of following: the newest line leaves at least `reserve` screen
-- rows free below it. It is a floor, not an exact value: with 'smoothscroll'
-- off, a scroll moves whole lines, so a wrapped top line cannot land on an
-- exact room. Scrolling up to chase one would move the text back and forth on
-- every tick, so the edge only ever scrolls down, and stops once it is clear.
function sticky_bottom.edge(window, reserve)
  if not window:is_valid() then return end

  local room = sticky_bottom.room(window)

  reserve = reserve or sticky_bottom.margin(window)

  if room < reserve then window:scroll_down(reserve - room) end
end

function sticky_bottom.pin(window, reserve)
  if not window:is_valid() then return end

  window:set_cursor({ window:get_buffer():get_line_count(), 0 })
  sticky_bottom.edge(window, reserve)
end

function sticky_bottom.tail(window, with_cursor, reserve)
  if not window:is_valid() then return end

  sticky_bottom.edge(window, reserve)

  if with_cursor then window:set_cursor({ window:get_buffer():get_line_count(), 0 }) end
end

return sticky_bottom

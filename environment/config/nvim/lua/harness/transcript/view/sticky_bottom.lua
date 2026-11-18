local geometry = require('harness.ui.composer_geometry')

local sticky_bottom = {}

function sticky_bottom.margin(window)
  return math.min(geometry.footprint(), math.floor(window:get_height() / 3))
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

return sticky_bottom

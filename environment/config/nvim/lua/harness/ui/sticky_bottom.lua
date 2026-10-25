local lazy = require('core.lazy')

local ComposerView = lazy('harness.ui.ComposerView')

local sticky_bottom = {}

function sticky_bottom.composer_rows()
  return ComposerView.footprint()
end

function sticky_bottom.margin(window)
  return math.min(sticky_bottom.composer_rows(), math.floor(window:get_height() / 3))
end

function sticky_bottom.at_end(window)
  if not window:is_valid() then return false end

  return select(2, window:get_visible_range()) >= window:get_buffer():get_line_count()
end

function sticky_bottom.pin(window, reserve)
  if not window:is_valid() then return end

  local last = window:get_buffer():get_line_count()

  reserve = reserve or sticky_bottom.margin(window)
  window:set_cursor({ last, 0 })

  if window:get_text_height(0, last - 1) > window:get_height() - reserve then
    window:scroll_to('bottom'):scroll_down(reserve)
  end
end

function sticky_bottom.tail(window, with_cursor, reserve)
  if not window:is_valid() then return end

  local last = window:get_buffer():get_line_count()

  sticky_bottom.hold(window, reserve or sticky_bottom.margin(window))

  if with_cursor then window:set_cursor({ last, 0 }) end
end

function sticky_bottom.room(window)
  local last = window:get_buffer():get_line_count()
  local top = window:get_visible_range()

  return window:get_height() - window:get_text_height(top, last - 1)
end

function sticky_bottom.hold(window, room)
  if not window:is_valid() then return end

  local short = room - sticky_bottom.room(window)

  if short > 0 then window:scroll_down(short) end
end

function sticky_bottom.release(window, rows, keep)
  if not window:is_valid() then return end

  local spare = sticky_bottom.room(window) - keep

  if spare > 0 and rows > 0 then window:scroll_up(math.min(rows, spare)) end
end

return sticky_bottom

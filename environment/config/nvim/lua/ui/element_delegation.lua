local VARIADIC = -1

local CHAINED = {
  set_lines = 1,
  clear_lines = 0,
  append = 1,
  set_text = 5,
  set_cursor = 1,
  set_lnum = 1,
  scroll_to = 2,
  reset_cursor = 0,
  set_width = 1,
  set_height = 1,
  focus = 0,
  start_insert = 0,
  stop_insert = 0,
  set_filetype = 1,
  clear_extmarks = 0,
  clear_extmark_lnums = 0,
  clear_extmark_texts = 0,
  clear_extmark_signs = 0,
  clear_extmark_highlights = VARIADIC,
  set_keymap = 4,
  on = 2,
  attach_to_changes = 1,
  call = 1,
  set_win_option = 2,
  enable_cursorline = 0,
  disable_cursorline = 0,
  attach_to_renderer = 1,
  detach_from_renderer = 0,
}

local READS = {
  get_lines = 0,
  get_line_count = 0,
  get_cursor = 0,
  get_lnum = 0,
  get_width = 0,
  get_height = 0,
  get_filetype = 0,
}

local FORWARDED = {
  place_extmark_text = 1,
  place_extmark_lnum = 1,
  place_extmark_sign = 1,
  place_extmark_highlight = 1,
  place_extmark_virt_lines = 1,
}

local function forwarded(name, arity)
  return function(self, ...)
    local args = { ... }
    local count = arity == VARIADIC and select('#', ...) or arity

    return self:with_element(function(el)
      return el[name](el, unpack(args, 1, count))
    end)
  end
end

local function chained(name, arity)
  local forward = forwarded(name, arity)

  return function(self, ...)
    forward(self, ...)

    return self
  end
end

local function define_single_element_methods(Class, opts)
  local exclude = opts and opts.exclude or {}

  for name, arity in pairs(CHAINED) do
    Class[name] = chained(name, arity)
  end

  for name, arity in pairs(READS) do
    if not exclude[name] then Class[name] = forwarded(name, arity) end
  end

  for name, arity in pairs(FORWARDED) do
    Class[name] = forwarded(name, arity)
  end

  local on_click = forwarded('on_click', 2)
  local is_focused = forwarded('is_focused', 0)

  function Class:on_click(clicks, click_opts)
    return on_click(self, clicks, click_opts) or function() end
  end

  function Class:is_focused()
    return is_focused(self) or false
  end

  function Class:is_valid()
    return self:with_element(function()
      return true
    end) or false
  end
end

return {
  define_single_element_methods = define_single_element_methods,
}

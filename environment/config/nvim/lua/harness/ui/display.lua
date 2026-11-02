local lazy = require('core.lazy')

local Buffer = lazy('core.Buffer')
local Window = lazy('core.Window')
local composer = require('harness.ui.composer')
local TranscriptView = lazy('harness.ui.TranscriptView')

local display = {}

local views = {}
local current = {}

function display.view(buf)
  return views[buf or Buffer.current_number()]
end

function display.shown()
  local out, seen = {}, {}

  for _, window in ipairs(Window.list_tab()) do
    local view = views[window:get_buffer().bufnr]

    if view and not seen[view] then
      seen[view] = true
      out[#out + 1] = view
    end
  end

  return out
end

function display.set_current(view)
  local tab = Window.current_tab()

  if current[tab] == view.bufnr then return end

  current[tab] = view.bufnr

  for _, shown in ipairs(display.shown()) do
    for _, window in ipairs(shown:windows()) do
      shown:set_winbar(window)
    end
  end
end

function display.view_of(session)
  for buf, view in pairs(views) do
    if view.session == session and Buffer.exists(buf) then return view end
  end
end

function display.showing(session)
  local view = display.view_of(session)

  return view ~= nil and view:is_visible()
end

function display.buffer_of(session)
  local view = display.view_of(session)

  return view and view.bufnr or nil
end

function display.window()
  for _, window in ipairs(Window.list_tab()) do
    if views[window:get_buffer().bufnr] then return window.win_id end
  end
end

function display.last()
  local buf = current[Window.current_tab()]

  if buf and Buffer.exists(buf) and views[buf] then return views[buf] end

  local win_id = display.window()

  return win_id and views[Window(win_id):get_buffer().bufnr] or nil
end

local function create(session, opts)
  local view = TranscriptView(session, {
    composer = composer,
    display = display,
    source_win = opts.source_win,
    source_buf = opts.source_buf,
  })

  views[view.bufnr] = view
  view:bind(view:bindings())
  view:mount({
    on_enter = function()
      display.set_current(view)
    end,
    on_dispose = function()
      views[view.bufnr] = nil

      for tab, buf in pairs(current) do
        if buf == view.bufnr then current[tab] = nil end
      end
    end,
  })

  return view
end

function display.open(session, opts)
  opts = opts or {}

  local view = display.view_of(session)

  if not view then
    view = create(session, opts)
  elseif opts.source_win then
    view.source_win = opts.source_win
    view.source_buf = opts.source_buf
  end

  if not opts.background then
    local window = Window.get_current()

    if composer.owns(window:get_buffer().bufnr) then
      -- the transcript never takes the composer's window: it goes to a window
      -- already showing it, or into a split of its own
      window = view:windows()[1] or Window.split_top()
    end

    view:show_in(window)
    display.set_current(view)
  end

  return view.bufnr
end

function display.target()
  local shown = display.shown()
  local view = display.last()

  if view then
    if #shown == 0 then return view end

    for _, candidate in ipairs(shown) do
      if candidate == view then return view end
    end
  end

  if #shown == 0 then return nil end
  if #shown == 1 then return shown[1] end

  return nil, shown
end

function display.is_target(view, window)
  if window:get_tab() ~= Window.current_tab() then return false end
  if display.last() ~= view then return false end

  return #display.shown() > 1
end

function display.forget(session)
  local view = display.view_of(session)

  if view then pcall(view.buffer.delete, view.buffer, { force = true }) end
end

function display.reveal(session, origin, source)
  local view = display.view_of(session)
  local window = origin and Window(origin)

  if view and view:is_visible() then
    -- the window the composer came from, or the first one showing the transcript
    if not (window and window:is_valid() and window:get_buffer().bufnr == view.bufnr) then
      window = view:windows()[1]
    end

    view:land(window)

    return window.win_id
  end

  if window and window:is_valid() then
    window:focus()
  else
    window = Window.split_top()
    window:reset_options({ 'winfixheight', 'signcolumn', 'winbar' })
  end

  display.open(session, { source_win = source.win, source_buf = source.buf })

  return Window.get_current().win_id
end

return display

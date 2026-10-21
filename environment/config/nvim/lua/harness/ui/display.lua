local lazy = require('core.lazy')

local Buffer = require('core.Buffer')
local TranscriptView = require('harness.ui.TranscriptView')
local Window = require('core.Window')

local transcript = lazy('harness.ui.transcript')

local display = {}

local views = {}
local last_buf

function display.view(buf)
  return views[buf or Buffer.current_number()]
end

function display.views()
  return views
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

function display.last()
  return last_buf and Buffer.exists(last_buf) and views[last_buf] or nil
end

function display.window()
  for _, window in ipairs(Window.list_tab()) do
    if views[window:get_buffer().bufnr] then return window.win_id end
  end
end

function display.to_bottom(win)
  TranscriptView.to_bottom(Window(win))
end

local function create(session, opts)
  local view = TranscriptView(session, opts)

  views[view.bufnr] = view
  view:bind(transcript.bindings(view))
  view:mount({
    on_enter = function()
      last_buf = view.bufnr
    end,
    on_dispose = function()
      views[view.bufnr] = nil
      if last_buf == view.bufnr then last_buf = nil end
    end,
  })

  return view
end

function display.open(session, opts)
  opts = opts or {}

  local view = display.view_of(session) or create(session, opts)

  if opts.source_win then
    view.source_win = opts.source_win
    view.source_buf = opts.source_buf
  end

  if not opts.background then
    view:show_in(Window.get_current())
    last_buf = view.bufnr
  end

  return view.bufnr
end

function display.forget(session)
  local view = display.view_of(session)

  if view then pcall(view.buffer.delete, view.buffer, { force = true }) end
end

function display.reveal(session, origin, source)
  local view = display.view_of(session)

  if view and view:is_visible() then return end

  local window = origin and Window(origin)

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

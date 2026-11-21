local lazy = require('core.lazy')

local guides = lazy('ui.guides')
local fs = lazy('core.system.fs')
local panes = lazy('core.editor.panes')
local Window = lazy('core.editor.Window')
local display = lazy('harness.ui.display')

local scene = {}

local function place(window)
  local name = window:get_buffer():get_name()

  return string.format('%s:%d', name ~= '' and fs.display(name) or '[No Name]', window:get_cursor()[1])
end

local function chat_on_screen(session)
  local view = display.view_of(session)

  for _, window in ipairs(view and view:windows() or {}) do
    if window:get_tab() == Window.current_tab() then return true end
  end

  return false
end

function scene.notes(session, opts)
  opts = opts or {}

  local notes = {}
  local mine = panes.list(session.key)

  if opts.from then
    notes[#notes + 1] =
      string.format('This prompt was drafted for session %s and moved here; you cannot see that session.', opts.from)
  end

  if not chat_on_screen(session) then
    notes[#notes + 1] = 'Your chat is not on screen: keep the reply short and use show to put code in front of them.'
  end

  local window = opts.win and Window(opts.win)
  local tag = window and window:is_valid() and window:get_var(panes.VAR)

  if type(tag) == 'table' and tag.owner == session.key then
    notes[#notes + 1] = string.format('They are in the "%s" pane you opened.', tag.name)
  end

  if #mine > 0 then
    local shown = {}

    for _, pane in ipairs(mine) do
      shown[#shown + 1] = pane.name .. ' ' .. place(pane.window)
    end

    notes[#notes + 1] = 'Panes you opened: ' .. table.concat(shown, ', ') .. '.'
  end

  local painted = #guides.list(session.key)

  if painted > 0 then
    notes[#notes + 1] =
      string.format('This prompt clears the %d note%s from your last show.', painted, painted == 1 and '' or 's')
  end

  return notes
end

return scene

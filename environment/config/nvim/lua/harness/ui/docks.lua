local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local event = lazy('core.event')
local Window = lazy('core.Window')
local Dock = lazy('harness.ui.Dock')

local docks = {}

docks.NO_SESSION = 'no session in this tab to dock; start one with :HarnessNew'

local by_tab = {}
local group

local function prune()
  for tab in pairs(by_tab) do
    if not Window.tab_valid(tab) then by_tab[tab] = nil end
  end
end

function docks.of(tab)
  prune()

  return by_tab[tab or Window.current_tab()]
end

function docks.open_dock(tab)
  local dock = docks.of(tab)

  return dock and dock:is_open() and dock or nil
end

function docks.zoomed(tab)
  prune()

  tab = tab or Window.current_tab()

  for _, dock in pairs(by_tab) do
    if dock:is_zoomed() and dock.zoom:get_tab() == tab then return dock end
  end
end

local function dock_of(tab)
  local dock = docks.of(tab)

  if not dock then
    dock = Dock(tab or Window.current_tab())
    by_tab[dock.tab] = dock
  end

  return dock
end

local function ensure(view, preset)
  local dock = docks.zoomed() or dock_of()

  if dock:is_zoomed() then dock:zoom_out() end

  if not dock:is_open() then
    if not view then return nil, docks.NO_SESSION end

    dock:open(view, preset)
  elseif preset then
    dock:resize(preset)
  end

  return dock
end

function docks.close()
  local dock = docks.zoomed() or docks.of()

  if not dock then return true end

  if dock:is_zoomed() then dock:zoom_out() end

  dock:close()

  return true
end

function docks.cycle(view)
  local zoomed = docks.zoomed()

  if zoomed then
    zoomed:zoom_out():resize(Dock.PRESET.compact)
    zoomed:focus()

    return true
  end

  local dock = docks.open_dock()

  if not dock then
    local opened, why = ensure(view, Dock.PRESET.compact)

    if not opened then return false, why end

    opened:focus()

    return true
  end

  if dock.preset == Dock.PRESET.half then return docks.zoom(view) end

  dock:resize(dock.preset == Dock.PRESET.compact and Dock.PRESET.half or Dock.PRESET.compact)

  return true
end

function docks.zoom(view)
  local dock, why = ensure(view)

  if not dock then return false, why end

  dock:zoom_in()

  return true
end

function docks.run(action, view)
  if action == '' or action == nil then return docks.cycle(view) end
  if action == 'close' then return docks.close() end
  if action == 'zoom' then return docks.zoom(view) end

  local preset = Dock.PRESET[action] or (action == 'open' and Dock.PRESET.compact)

  if not preset then return false, 'choose open, compact, half, zoom or close' end

  local dock, why = ensure(view, preset)

  if not dock then return false, why end

  dock:focus()

  return true
end

function docks.register_events()
  if group then group.dispose() end

  group = event.augroup('harness.docks')

  group.on('WinClosed', function(args)
    local win_id = tonumber(args.match)

    for _, dock in pairs(by_tab) do
      if dock.window and dock.window.win_id == win_id then dock.window = nil end

      if dock.zoom and dock.zoom.win_id == win_id then
        Timer.defer(0, function()
          if dock.zoom and not dock.zoom:is_valid() then dock:zoom_out() end
        end)
      end
    end
  end)

  group.on('WinResized', function()
    for _, dock in pairs(by_tab) do
      dock:observe()
    end
  end)

  return docks
end

function docks.reset()
  for tab in pairs(by_tab) do
    by_tab[tab] = nil
  end

  if group then group.dispose() end

  group = nil
end

return docks

local Buffer = require('core.Buffer')
local Window = require('core.Window')

local surfaces = {}

local open = {}
local order = {}
local recent = {}
local next_id = 0

local RECENT = 20

function surfaces.add(surface)
  next_id = next_id + 1
  surface.id = 'u' .. next_id
  open[surface.id] = surface
  order[#order + 1] = surface.id

  surface:on('close', function()
    open[surface.id] = nil
    table.insert(recent, 1, surface)
    recent[RECENT + 1] = nil
  end)

  return surface
end

function surfaces.get(id)
  local surface = open[id]

  if surface and not surface:is_open() then
    open[id] = nil
    return nil
  end

  return surface
end

function surfaces.find(id)
  local surface = surfaces.get(id)

  if surface then return surface end

  for _, closed in ipairs(recent) do
    if closed.id == id then return closed end
  end
end

function surfaces.all()
  local out = {}

  for _, id in ipairs(order) do
    local surface = surfaces.get(id)
    if surface then out[#out + 1] = surface end
  end

  order = vim.tbl_map(function(surface)
    return surface.id
  end, out)

  return out
end

function surfaces.close_all()
  for _, surface in ipairs(surfaces.all()) do
    surface:close()
  end
end

function surfaces.jump(item, how, win)
  local origin = win and Window(win)

  if origin and origin:is_valid() then origin:focus() end

  local bufnr = item.data and item.data.bufnr

  if Buffer.exists(bufnr) and (how or 'edit') == 'edit' then
    Window.get_current():set_buffer(Buffer(bufnr))
  elseif item.path then
    Window.open_path(item.path, how)
  else
    return
  end

  if item.line then
    local window = Window.get_current()
    local last = window:get_buffer():get_line_count()

    pcall(window.set_cursor, window, { math.min(item.line, last), math.max((item.col or 1) - 1, 0) })
    window:normal('zz')
  end
end

function surfaces.pick(opts)
  return surfaces.add(require('surfaces.Picker')(opts)):open()
end

function surfaces.list(opts)
  return surfaces.add(require('surfaces.List')(opts)):open()
end

function surfaces.panel(opts)
  return surfaces.add(require('surfaces.Panel')(opts)):open()
end

return surfaces

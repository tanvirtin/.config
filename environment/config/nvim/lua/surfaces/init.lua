local Buffer = require('core.editor.Buffer')
local Window = require('core.editor.Window')

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
  local origin = Window.find(win)

  if origin then origin:focus() end

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

    window:set_cursor({ math.min(item.line, last), math.max((item.col or 1) - 1, 0) })
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

function surfaces.info(opts)
  return surfaces.add(require('surfaces.InfoLens')(opts or {})):begin()
end

function surfaces.scene(opts)
  local scene = surfaces.add(require('surfaces.Scene')(opts))
  local ok, err = pcall(scene.open, scene)

  if not ok then
    scene:close()
    error(err, 0)
  end

  return scene
end

function surfaces.canvas(opts)
  return surfaces.add(require('surfaces.Canvas')(opts)):open()
end

return surfaces

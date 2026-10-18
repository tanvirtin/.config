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

local OPEN = { edit = 'edit', split = 'split', vsplit = 'vsplit', tab = 'tabedit' }

function surfaces.jump(item, how, win)
  if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end

  local bufnr = item.data and item.data.bufnr

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and (how or 'edit') == 'edit' then
    vim.api.nvim_set_current_buf(bufnr)
  elseif item.path then
    vim.cmd((OPEN[how or 'edit'] or 'edit') .. ' ' .. vim.fn.fnameescape(item.path))
  else
    return
  end

  if item.line then
    local last = vim.api.nvim_buf_line_count(0)

    pcall(vim.api.nvim_win_set_cursor, 0, { math.min(item.line, last), math.max((item.col or 1) - 1, 0) })
    vim.cmd('normal! zz')
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

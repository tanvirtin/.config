local Window = require('core.editor.Window')
local buffers = require('core.editor.buffers')

local panes = {}

panes.VAR = 'pane'
panes.WIDE = 2.2
panes.MIN_WIDTH = 60

local function tag(window)
  local value = window:get_var(panes.VAR)

  return type(value) == 'table' and value or nil
end

local function tiled()
  local out = {}

  for _, window in ipairs(Window.list_tab()) do
    if not window:is_floating() then out[#out + 1] = window end
  end

  return out
end

function panes.list(owner)
  local out = {}

  for _, window in ipairs(tiled()) do
    local t = tag(window)

    if t and (owner == nil or t.owner == owner) then
      out[#out + 1] = { owner = t.owner, name = t.name, window = window }
    end
  end

  return out
end

function panes.find(owner, name)
  for _, pane in ipairs(panes.list(owner)) do
    if pane.name == name then return pane.window end
  end

  return nil
end

function panes.side_by_side(window)
  local width, height = window:get_width(), math.max(window:get_height(), 1)

  return width >= panes.MIN_WIDTH * 2 and width / height >= panes.WIDE
end

local function host(anchor)
  local best, area

  for _, window in ipairs(tiled()) do
    if not (anchor and window:is_same(anchor)) then
      local size = window:get_width() * window:get_height()

      if not best or size > area then
        best, area = window, size
      end
    end
  end

  return best or anchor or Window.get_current()
end

local function side(window, anchor)
  local wide = panes.side_by_side(window)
  local beside_anchor = anchor and window:is_same(anchor)

  if wide then return beside_anchor and 'left' or 'right' end

  return beside_anchor and 'above' or 'below'
end

function panes.show(owner, anchor, name, target, opts)
  opts = opts or {}
  name = name or 'code'

  local buffer = type(target) == 'string' and buffers.load(target) or target
  local window = panes.find(owner, name)

  if window then
    window:set_buffer(buffer)
  else
    local base = host(anchor)

    window = base:open_split(buffer, side(base, anchor))
    window:set_var(panes.VAR, { owner = owner, name = name })
  end

  if opts.line then
    window:set_cursor({ math.min(opts.line, buffer:get_line_count()), 0 })
    window:scroll_to('center')
  end

  if opts.focus then window:focus() end

  return window
end

function panes.close(owner, name)
  local closed = 0

  for _, pane in ipairs(panes.list(owner)) do
    if name == nil or pane.name == name then
      pane.window:close()
      closed = closed + 1
    end
  end

  return closed
end

return panes

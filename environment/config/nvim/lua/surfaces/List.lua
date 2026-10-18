local Surface = require('surfaces.Surface')
local View = require('ui.View')
local LinesComponent = require('ui.components.LinesComponent')
local compact = require('compact')
local schema = require('nvim_mcp.schema')

local List = Surface:extend()

function List:constructor(opts)
  local instance = Surface.constructor(self, { kind = 'list', title = opts.title or 'List', owner = opts.owner })

  instance._items = compact.order(opts.items or {})
  instance._height = opts.height
  instance._rows = {}

  return instance
end

function List:render()
  local lines = { string.format('%s (%d)', self.title, #self._items) }
  local highlights = { { row = 0, from = 0, to = #lines[1], hl = 'UiTitle' } }
  local rows, lnums = {}, {}
  local current

  for index, item in ipairs(self._items) do
    local key = item.path or '[No Name]'

    if key ~= current then
      current = key
      lines[#lines + 1] = compact.path(item.path)
      highlights[#highlights + 1] = { row = #lines - 1, from = 0, to = #lines[#lines], hl = 'UiPath' }
    end

    local where = string.format('  %4s', item.line or '')
    lines[#lines + 1] = where .. '  ' .. compact.line(item.text or '', 200)
    highlights[#highlights + 1] = { row = #lines - 1, from = 0, to = #where, hl = 'UiLineNr' }
    rows[#lines] = item
    lnums[index] = #lines
  end

  return lines, highlights, rows, lnums
end

function List:_refresh()
  local lines, highlights, rows, lnums = self:render()

  self._rows, self._lnums = rows, lnums

  if self._body then self._body:set_content(lines, highlights) end

  return lines
end

function List:_index(index)
  local item = self._items[index]

  if not item then error(string.format('no item %d (the list has %d)', index, #self._items), 0) end

  return item
end

function List:item_at(lnum)
  return self._rows[lnum]
end

function List:open()
  local lines, highlights, rows, lnums = self:render()

  self._rows, self._lnums = rows, lnums
  self._origin = vim.api.nvim_get_current_win()
  self._body = LinesComponent({ lines = lines, highlights = highlights, filetype = 'surface_list' })
  self._view = View()
  self._view:_render({
    component = self._body,
    mode = 'split',
    split_height = self._height or math.min(#lines, 15),
  })

  local function open_current(how)
    local item = self:item_at(self._body:get_lnum())

    if item then self:_open(item, how) end
  end

  self._body:set_keymap('n', '<CR>', function()
    open_current('edit')
  end, 'Open')
  self._body:set_keymap('n', '<2-LeftMouse>', function()
    open_current('edit')
  end, 'Open')
  self._body:set_keymap('n', '<C-v>', function()
    open_current('vsplit')
  end, 'Open in a vertical split')
  self._body:set_keymap('n', 'q', function()
    self:close()
  end, 'Close')

  for lnum = 1, #lines do
    if rows[lnum] then
      self._body:set_lnum(lnum)
      break
    end
  end

  self:set_state('ready')

  return self
end

function List:_open(item, how)
  self:emit('select', item, how)
  require('surfaces').jump(item, how, self._origin)
end

local LOCATION = schema.model({
  { name = 'path', type = schema.str() },
  { name = 'line', type = schema.int(), optional = true },
  { name = 'col', type = schema.int(), optional = true },
  { name = 'text', type = schema.str(), optional = true },
})

List.LOCATION = LOCATION

List.COMMANDS = {
  cursor = {
    summary = 'Put the cursor on item index (1-based, in the order shown), to point the user at it.',
    params = { { name = 'index', type = schema.int() } },
    run = function(self, args)
      self:_index(args.index)
      self._body:set_lnum(self._lnums[args.index])
    end,
  },
  open = {
    summary = 'Open item index (default: the one under the cursor) in the window above (how: edit, split, vsplit, tab).',
    params = {
      { name = 'index', type = schema.int(), optional = true },
      { name = 'how', type = schema.literal({ 'edit', 'split', 'vsplit', 'tab' }), optional = true },
    },
    run = function(self, args)
      local item = args.index and self:_index(args.index) or self:item_at(self._body:get_lnum())

      if item then self:_open(item, args.how or 'edit') end
    end,
  },
  add = {
    summary = 'Add locations to the list, to build it up as results arrive.',
    params = { { name = 'items', type = schema.list(LOCATION) } },
    run = function(self, args)
      vim.list_extend(self._items, args.items)
      self._items = compact.order(self._items)
      self:_refresh()
    end,
  },
}

function List:snapshot(budget)
  local selected = self._body and self._body:is_valid() and self:item_at(self._body:get_lnum())
  local head = string.format('%s: list "%s" [%s]', self.id, self.title, self.state)

  if selected then
    head = head .. string.format(', cursor on %s:%d', compact.path(selected.path), selected.line or 0)
  end

  return head .. '\n' .. (compact.locations(self._items, { budget = budget }))
end

return List

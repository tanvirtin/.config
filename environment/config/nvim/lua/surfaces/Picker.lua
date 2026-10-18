local Surface = require('surfaces.Surface')
local View = require('ui.View')
local SearchComponent = require('ui.components.SearchComponent')
local compact = require('compact')
local sources = require('sources')

local schema = require('nvim_mcp.schema')

local Picker = Surface:extend()

local HOW = schema.literal({ 'edit', 'split', 'vsplit', 'tab' })

local LIVE_DELAY_MS = 120

function Picker:constructor(opts)
  local instance = Surface.constructor(self, { kind = 'picker', title = opts.title or opts.source, owner = opts.owner })

  instance._opts = opts
  instance._items = {}
  instance._cancel = nil
  instance._origin = nil

  return instance
end

local HINTS = {
  { '<CR>', 'open' },
  { '<C-v>/<C-s>/<C-t>', 'split/tab' },
  { '<C-q>', 'to list' },
  { '<C-n>/<C-p>', 'move' },
  { '<Esc>', 'close' },
}

function Picker.footer(hints)
  local chunks = { { ' ', 'UiMuted' } }

  for i, hint in ipairs(hints) do
    if i > 1 then chunks[#chunks + 1] = { '  ', 'UiMuted' } end

    chunks[#chunks + 1] = { hint[1], 'UiAccent' }
    chunks[#chunks + 1] = { ' ' .. hint[2], 'UiMuted' }
  end

  chunks[#chunks + 1] = { ' ', 'UiMuted' }

  return chunks
end

local function one_line(text)
  return text and (tostring(text):gsub('[\r\n]+', ' ')) or nil
end

local function entry(item)
  return {
    label = one_line(item.label) or compact.path(item.path),
    description = one_line(item.description),
    value = item,
  }
end

function Picker:_show(items, live)
  self._items = items

  if not (self._search and self._search:is_mounted()) then return end

  if live then
    self._search:set_items(vim.tbl_map(entry, items))
  else
    self._search:update_items(vim.tbl_map(entry, items))
  end
end

function Picker:_collect(query)
  if self._cancel then self._cancel() end

  local items, scheduled = {}, false
  local source = sources.get(self._opts.source)

  if not source then
    return vim.notify('Picker: unknown source ' .. tostring(self._opts.source), vim.log.levels.WARN)
  end

  self:set_state('loading')
  self._cancel = source.collect(source.live and query or '', self._opts.source_opts or {}, function(batch)
    vim.list_extend(items, batch)

    if scheduled then return end

    scheduled = true
    vim.defer_fn(function()
      scheduled = false
      self:_show(items, source.live)
    end, 30)
  end, function(err)
    self:_show(items, source.live)
    if self.state == 'loading' then self:set_state('ready') end
    if err then vim.notify(self.title .. ': ' .. err, vim.log.levels.WARN) end
  end)
end

function Picker:_choose(how)
  local selected = self._search and self._search:get_selected_item()
  local item = selected and selected.value
  local origin = self._origin

  self._chosen = item
  self:close()
  if item then self:set_state('chosen') end

  if not item then return end

  vim.schedule(function()
    self:emit('select', item, how)

    if self._opts.on_select then
      self._opts.on_select(item, how)
    else
      require('surfaces').jump(item, how, origin)
    end
  end)
end

function Picker:_send_to_list()
  local items = vim.tbl_map(function(e)
    return e.value
  end, self._search and self._search.state.filtered_items or {})

  self:close()

  vim.schedule(function()
    require('surfaces').list({ title = self.title, items = items, owner = self.owner })
  end)
end

function Picker:open()
  local source = self._opts.source and sources.get(self._opts.source)
  local live = source and source.live
  local delay

  self._origin = vim.api.nvim_get_current_win()
  self._search = SearchComponent({
    prompt = (self.title or '') .. ' > ',
    items = self._opts.items and vim.tbl_map(entry, self._opts.items) or {},
    width = self._opts.width,
    max_height = self._opts.max_height,
    footer = Picker.footer(self:hints()),
    placeholder = live and 'Type to search…' or 'No matches',
    on_select = function()
      self:_choose('edit')
    end,
    on_close = function()
      self:close()
    end,
    on_search_async = live and function(query)
      if delay then delay:stop() end
      delay = vim.defer_fn(function()
        self:_collect(query)
      end, LIVE_DELAY_MS)
    end or nil,
  })

  self._view = View()
  self._view:_render({ component = self._search, mode = 'popup' })

  for key, how in pairs({ ['<C-v>'] = 'vsplit', ['<C-s>'] = 'split', ['<C-t>'] = 'tab' }) do
    self._search:set_keymap('i', key, function()
      self:_choose(how)
    end, 'Open in ' .. how)
  end

  self._search:set_keymap('i', '<C-q>', function()
    self:_send_to_list()
  end, 'Send matches to a list')

  for _, action in ipairs(self._opts.actions or {}) do
    for _, mode in ipairs({ 'i', 'n' }) do
      self._search:set_keymap(mode, action.key, function()
        action.run(self:selected(), self)
      end, action.desc)
    end
  end

  if self._opts.items then self._items = self._opts.items end

  self:set_state('ready')

  if source and not live then self:_collect('') end

  if self._opts.query and self._opts.query ~= '' then vim.api.nvim_feedkeys(self._opts.query, 'n', false) end

  return self
end

Picker.COMMANDS = {
  query = {
    summary = 'Type a query: the list filters, or a live source (grep) searches.',
    params = { { name = 'text', type = schema.str() } },
    run = function(self, args)
      self._search:set_query(args.text)
    end,
  },
  move = {
    summary = 'Move the selection down (or up) count times.',
    params = {
      { name = 'direction', type = schema.literal({ 'down', 'up' }), optional = true },
      { name = 'count', type = schema.int(), optional = true },
    },
    run = function(self, args)
      for _ = 1, math.max(args.count or 1, 1) do
        self._search:move(args.direction or 'down')
      end
    end,
  },
  select = {
    summary = 'Choose the selected item, as <CR> does (how: edit, split, vsplit, tab).',
    params = { { name = 'how', type = HOW, optional = true } },
    run = function(self, args)
      self:_choose(args.how or 'edit')
    end,
  },
}

function Picker:hints()
  if self._opts.hints then return self._opts.hints end

  local hints = vim.deepcopy(HINTS)

  for _, action in ipairs(self._opts.actions or {}) do
    table.insert(hints, #hints, { action.key, action.desc })
  end

  return hints
end

function Picker:selected()
  local selected = self._search and self._search:get_selected_item()

  return selected and selected.value
end

function Picker:set_items(items)
  self._opts.items = items
  self:_show(items, false)
end

function Picker:chosen()
  return self._chosen
end

function Picker:close()
  if self._cancel then self._cancel() end

  Surface.close(self)
end

function Picker:snapshot(budget)
  local search = self._search
  local state = search and search.state or {}
  local matches = state.filtered_items or {}
  local selected = search and search:get_selected_item()
  local lines = {
    string.format(
      '%s: picker "%s" [%s], query "%s", %d of %d items',
      self.id,
      self.title,
      self.state,
      state.query or '',
      #matches,
      #self._items
    ),
  }

  if self._chosen then
    lines[#lines + 1] = 'chosen: ' .. (self._chosen.label or compact.path(self._chosen.path))
    return table.concat(lines, '\n')
  end

  if selected then lines[#lines + 1] = 'selected: ' .. selected.label end

  local labels = vim.tbl_map(function(e)
    return { label = e.label }
  end, matches)

  lines[#lines + 1] = compact.rows(labels, { 'label' }, { budget = budget or compact.BUDGET }):gsub('^label\n?', '')

  return table.concat(lines, '\n')
end

return Picker

local compact = require('compact')
local schema = require('nvim_mcp.schema')
local sources = require('sources')
local surfaces = require('surfaces')
local util = require('nvim_mcp.tools.util')

local WAIT_MS = 2000

local function surface(id)
  local found = surfaces.find(id)

  if not found then util.fail('no surface ' .. tostring(id) .. ' (ui_surfaces lists them)') end

  return found
end

local function source_opts(args)
  if args.source == 'lsp' then
    local buf = util.resolve(args)
    local line, col = args.line, args.col

    if not line and buf == util.focused_buf() then
      local cursor = util.focused_cursor()
      line, col = cursor[1], cursor[2] + 1
    end

    if not line then util.fail('pass line (and col): the cursor is only known for the focused buffer') end

    return { method = args.method or 'references', buf = buf, line = line, col = col }
  end

  if args.source == 'diagnostics' then return { buf = (args.path or args.bufnr) and util.resolve(args) or nil } end

  return { cwd = args.path and vim.fs.normalize(vim.fn.fnamemodify(args.path, ':p')) or nil }
end

local function render(items, args)
  local located = #items > 0 and items[1].line ~= nil

  if located then return (compact.locations(items, { budget = args.budget, offset = args.offset })) end

  local rows = vim.tbl_map(function(item)
    return { label = item.label or compact.path(item.path) }
  end, vim.list_slice(items, (args.offset or 0) + 1))

  if #items == 0 then return 'no results' end

  return string.format('%d results\n', #items)
    .. compact.rows(rows, { 'label' }, { budget = args.budget }):gsub('^label\n', '')
end

local function search(args, ctx)
  local opts = source_opts(args)
  local items, err = sources.collect(args.source, args.query or '', opts)
  local text = render(items, args)

  if err then text = text .. '\n(' .. err .. ')' end

  if args.show then
    local picker = surfaces.pick({
      title = args.source,
      source = args.source,
      source_opts = opts,
      owner = ctx.caller,
    })

    if args.query and args.query ~= '' then picker:command('query', { text = args.query }) end

    text = text .. '\nshown to the user in ' .. picker.id .. ' (drive it with ui_command)'
  end

  return compact.reply(ctx.caller, items, text)
end

local function ui_show(args, ctx)
  local shown

  if args.kind == 'list' then
    shown = surfaces.list({ title = args.title, items = args.items or {}, owner = ctx.caller })
  else
    shown = surfaces.panel({ title = args.title, markdown = args.markdown or '', owner = ctx.caller })
  end

  return shown:describe()
end

local function ui_pick(args, ctx)
  local items = args.items and vim.tbl_map(function(label)
    return { label = label }
  end, args.items)

  local picker = surfaces.pick({
    title = args.title,
    source = not items and args.source or nil,
    items = items,
    owner = ctx.caller,
    on_select = function() end,
  })

  if args.query then picker:command('query', { text = args.query }) end

  return picker:describe() .. '\nthe user is choosing; ui_read ' .. picker.id .. ' shows their choice once made'
end

local function ui_surfaces()
  local all = surfaces.all()

  if #all == 0 then return 'no surfaces open' end

  return table.concat(
    vim.tbl_map(function(s)
      return s:describe()
    end, all),
    '\n'
  )
end

local function ui_read(args)
  return surface(args.surface):snapshot(args.budget)
end

local function ui_command(args)
  local target = surface(args.surface)
  local result = target:command(args.command, args.args or {})

  vim.wait(args.wait_ms or WAIT_MS, function()
    return target.state ~= 'loading'
  end, 10)

  local out = target:snapshot(args.budget)

  if result ~= nil then out = vim.inspect(result) .. '\n' .. out end

  return out
end

local function ui_screen(args, ctx)
  local text = util.screen(args.budget)

  return compact.reply(ctx.caller, text, text)
end

local function ui_keys(args, ctx)
  if args.win then vim.api.nvim_set_current_win(args.win) end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(args.keys, true, false, true), 'mx', false)

  return ui_screen({ budget = args.budget }, ctx)
end

local SOURCE_TARGET = {
  {
    name = 'path',
    type = schema.str({
      description = 'files/grep: directory to search (default cwd). lsp/diagnostics: the buffer (default focused).',
    }),
    optional = true,
  },
  { name = 'bufnr', type = schema.int(), optional = true },
}

return {
  {
    name = 'search',
    risk = 'read',
    summary = 'Search a source and get compact results at once: files (fuzzy path), grep (regex, smart case), lsp (method: definition, references, type_definition, implementation at line/col, default the cursor), diagnostics, buffers. show = true also plays the search out in a picker the user sees (optional: use it when showing your work helps).',
    params = util.params(
      {
        { name = 'source', type = schema.literal({ 'files', 'grep', 'lsp', 'diagnostics', 'buffers' }) },
        { name = 'query', type = schema.str(), optional = true },
      },
      SOURCE_TARGET,
      {
        {
          name = 'method',
          type = schema.literal({ 'definition', 'references', 'type_definition', 'implementation' }),
          optional = true,
        },
        { name = 'line', type = schema.int(), optional = true },
        { name = 'col', type = schema.int(), optional = true },
        {
          name = 'offset',
          type = schema.int({ description = 'Continue from a "… more (offset=N)" line.' }),
          optional = true,
        },
        {
          name = 'budget',
          type = schema.int({ description = 'Characters of output (default 6000).' }),
          optional = true,
        },
        { name = 'show', type = schema.bool(), optional = true },
      }
    ),
    fn = search,
  },
  {
    name = 'ui_show',
    risk = 'write',
    summary = 'Show the user a list of locations (kind = list: a split grouped by file; they press Enter to jump) or a markdown panel (kind = panel). Prefer this to writing a Lua script. Returns the surface id and its commands.',
    params = {
      { name = 'kind', type = schema.literal({ 'list', 'panel' }) },
      { name = 'title', type = schema.str() },
      { name = 'items', type = schema.list(require('surfaces.List').LOCATION), optional = true },
      { name = 'markdown', type = schema.str(), optional = true },
    },
    fn = ui_show,
  },
  {
    name = 'ui_pick',
    risk = 'write',
    summary = 'Ask the user to pick one of items (labels) or from a source, in a picker. Returns at once; ui_read the surface later for their choice.',
    params = {
      { name = 'title', type = schema.str() },
      { name = 'items', type = schema.list(schema.str()), optional = true },
      { name = 'source', type = schema.literal({ 'files', 'buffers', 'diagnostics' }), optional = true },
      { name = 'query', type = schema.str(), optional = true },
    },
    fn = ui_pick,
  },
  {
    name = 'ui_surfaces',
    risk = 'read',
    summary = 'Open surfaces (pickers, lists, panels): id, kind, title, state, owner, and the commands each takes.',
    params = {},
    fn = ui_surfaces,
  },
  {
    name = 'ui_read',
    risk = 'read',
    summary = 'What a surface shows, as compact text: its state, query, selection or choice, and items.',
    params = {
      { name = 'surface', type = schema.str() },
      { name = 'budget', type = schema.int(), optional = true },
    },
    fn = ui_read,
  },
  {
    name = 'ui_command',
    risk = 'write',
    summary = 'Drive a surface one step, as the user would with keys (picker: query, move, select; list: cursor, open, add; panel: write; all: close). Waits for loading to finish, then returns what it shows.',
    params = {
      { name = 'surface', type = schema.str() },
      { name = 'command', type = schema.str() },
      { name = 'args', type = schema.dict(schema.any()), optional = true },
      { name = 'wait_ms', type = schema.int(), optional = true },
      { name = 'budget', type = schema.int(), optional = true },
    },
    fn = ui_command,
  },
  {
    name = 'ui_screen',
    risk = 'read',
    summary = 'What the user sees now: every window of the current tab (floats included) with its buffer, visible lines and cursor (marked >), the mode, and open surfaces. Use it to read any UI, such as a vgit view.',
    params = { { name = 'budget', type = schema.int(), optional = true } },
    fn = ui_screen,
  },
  {
    name = 'ui_keys',
    risk = 'exec',
    summary = 'Type keys into the editor, with mappings, as the user would (e.g. "s" in a vgit diff view stages a hunk, "<C-w>j" moves down a window), optionally in window win first. Returns ui_screen afterwards.',
    params = {
      { name = 'keys', type = schema.str() },
      { name = 'win', type = schema.int(), optional = true },
      { name = 'budget', type = schema.int(), optional = true },
    },
    fn = ui_keys,
  },
}

local Buffer = require('core.Buffer')
local Window = require('core.Window')
local buffers = require('core.buffers')
local compact = require('compact')
local editor = require('core.editor')
local fs = require('core.fs')
local schema = require('nvim_mcp.schema')
local util = require('nvim_mcp.tools.util')

local function buf_name(buf)
  local path = util.buf_path(buf)

  return path and compact.path(path) or ('[No Name ' .. buf .. ']')
end

local function editor_state(_, ctx)
  local win = util.focused_win()
  local buf = util.focused_buf()
  local buffer = Buffer(buf)
  local cursor = util.focused_cursor()
  local shown = util.focus_shown()
  local lines = {
    string.format(
      'cwd %s, mode %s, tab %d of %d',
      compact.path(fs.local_cwd()),
      editor.mode(),
      editor.tab_number(),
      editor.tab_count()
    ),
    string.format(
      'focus: %s [%s] bufnr %d, %s, cursor %d:%d of %d lines%s',
      buf_name(buf),
      buffer:get_option('filetype'),
      buf,
      shown and ('win ' .. win) or 'not shown in a window',
      cursor[1],
      cursor[2] + 1,
      buffer:get_line_count(),
      buffer:get_option('modified') and ', unsaved changes' or ''
    ),
  }

  local vstart, vend = buffer:get_mark('<'), buffer:get_mark('>')

  if vstart[1] > 0 and vend[1] >= vstart[1] then
    local text = table.concat(buffer:get_lines(vstart[1] - 1, vend[1]), ' ')

    lines[#lines + 1] = string.format('last selection %d-%d: %s', vstart[1], vend[1], compact.line(text, 200))
  end

  local open = {}

  for _, b in ipairs(buffers.list()) do
    if b:is_listed() and b:is_loaded() then
      open[#open + 1] =
        string.format('%s (%d)%s', buf_name(b.bufnr), b.bufnr, b:get_option('modified') and ' [+]' or '')
    end
  end

  lines[#lines + 1] = 'buffers: ' .. table.concat(open, ', ')
  lines[#lines + 1] = 'tabs (* focus):'

  for _, tab in ipairs(editor.tabs()) do
    local windows = {}

    for _, w in ipairs(tab.windows) do
      windows[#windows + 1] =
        string.format('win %d %s%s', w.win_id, buf_name(w:get_buffer().bufnr), w.win_id == win and '*' or '')
    end

    lines[#lines + 1] = string.format('  %d: %s', tab.number, table.concat(windows, ', '))
  end

  local text = table.concat(lines, '\n')

  return compact.reply(ctx.caller, text, text)
end

local function open(args)
  local window = Window.tab_edit(args.path)
  local buffer = window:get_buffer()

  if args.line then window:move_cursor(math.min(args.line, buffer:get_line_count()), 0) end

  util.set_focus(window.win_id)

  return { path = util.buf_path(buffer.bufnr), bufnr = buffer.bufnr, win = window.win_id }
end

local function cursor_set(args)
  if not args.win and not util.focus_shown() then
    util.fail('bufnr ' .. util.focused_buf() .. ' is not shown in a window; open it first, or pass win')
  end

  local window = Window(args.win or util.focused_win())
  local line = math.min(args.line, window:get_buffer():get_line_count())

  window:move_cursor(line, (args.col or 1) - 1)

  return { win = window.win_id, line = line, col = args.col or 1 }
end

local function fs_find(args)
  return vim.fs.find(args.names, { path = args.path, type = args.type, limit = args.limit or 20 })
end

return {
  {
    name = 'editor_state',
    risk = 'read',
    summary = 'Where the user is, compactly: cwd and mode; the focused file with its bufnr, window and cursor; the last visual selection; open buffers ([+] unsaved); tabs with their windows. Call this first.',
    params = {},
    fn = editor_state,
  },
  {
    name = 'fs_find',
    risk = 'read',
    summary = 'Find files or directories by exact name, searching downward from path (default cwd).',
    params = {
      { name = 'names', type = schema.list(schema.str()) },
      { name = 'path', type = schema.str(), optional = true },
      { name = 'type', type = schema.literal({ 'file', 'directory' }), optional = true },
      { name = 'limit', type = schema.int(), optional = true },
    },
    fn = fs_find,
  },
  {
    name = 'open',
    risk = 'write',
    summary = 'Open a file in a new tab, optionally at a 1-based line. It becomes the focused buffer.',
    params = {
      { name = 'path', type = schema.str() },
      { name = 'line', type = schema.int(), optional = true },
    },
    fn = open,
  },
  {
    name = 'cursor_set',
    risk = 'write',
    summary = 'Move the cursor in the focused window (or win) to a 1-based line and column.',
    params = util.params({ { name = 'win', type = schema.int(), optional = true } }, util.POSITION),
    fn = cursor_set,
  },
}

local compact = require('compact')
local schema = require('nvim_mcp.schema')
local util = require('nvim_mcp.tools.util')

local function buf_name(buf)
  local path = util.buf_path(buf)

  return path and compact.path(path) or ('[No Name ' .. buf .. ']')
end

local function editor_state(_, ctx)
  local win = util.focused_win()
  local buf = util.focused_buf()
  local cursor = util.focused_cursor()
  local shown = util.focus_shown()
  local lines = {
    string.format(
      'cwd %s, mode %s, tab %d of %d',
      compact.path(vim.fn.getcwd()),
      vim.api.nvim_get_mode().mode,
      vim.fn.tabpagenr(),
      vim.fn.tabpagenr('$')
    ),
    string.format(
      'focus: %s [%s] bufnr %d, %s, cursor %d:%d of %d lines%s',
      buf_name(buf),
      vim.bo[buf].filetype,
      buf,
      shown and ('win ' .. win) or 'not shown in a window',
      cursor[1],
      cursor[2] + 1,
      vim.api.nvim_buf_line_count(buf),
      vim.bo[buf].modified and ', unsaved changes' or ''
    ),
  }

  local vstart, vend = vim.api.nvim_buf_get_mark(buf, '<'), vim.api.nvim_buf_get_mark(buf, '>')

  if vstart[1] > 0 and vend[1] >= vstart[1] then
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, vstart[1] - 1, vend[1], false), ' ')

    lines[#lines + 1] = string.format('last selection %d-%d: %s', vstart[1], vend[1], compact.line(text, 200))
  end

  local buffers = {}

  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b) then
      buffers[#buffers + 1] = string.format('%s (%d)%s', buf_name(b), b, vim.bo[b].modified and ' [+]' or '')
    end
  end

  lines[#lines + 1] = 'buffers: ' .. table.concat(buffers, ', ')
  lines[#lines + 1] = 'tabs (* focus):'

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local windows = {}

    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      windows[#windows + 1] =
        string.format('win %d %s%s', w, buf_name(vim.api.nvim_win_get_buf(w)), w == win and '*' or '')
    end

    lines[#lines + 1] = string.format('  %d: %s', vim.api.nvim_tabpage_get_number(tab), table.concat(windows, ', '))
  end

  local text = table.concat(lines, '\n')

  return compact.reply(ctx.caller, text, text)
end

local function open(args)
  vim.cmd('tabnew ' .. vim.fn.fnameescape(args.path))

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)

  if args.line then vim.api.nvim_win_set_cursor(win, { math.min(args.line, vim.api.nvim_buf_line_count(buf)), 0 }) end

  util.set_focus(win)

  return { path = util.buf_path(buf), bufnr = buf, win = win }
end

local function cursor_set(args)
  if not args.win and not util.focus_shown() then
    util.fail('bufnr ' .. util.focused_buf() .. ' is not shown in a window; open it first, or pass win')
  end

  local win = args.win or util.focused_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local line = math.min(args.line, vim.api.nvim_buf_line_count(buf))

  vim.api.nvim_win_set_cursor(win, { line, (args.col or 1) - 1 })

  return { win = win, line = line, col = args.col or 1 }
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

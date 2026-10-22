local Buffer = require('core.Buffer')
local compact = require('compact')
local schema = require('nvim_mcp.schema')

local util = {}

local focus = {}

function util.set_focus(win, buf)
  focus.win = win
  focus.buf = buf or (win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)) or nil
end

local function focus_buf()
  if not (focus.buf and vim.api.nvim_buf_is_valid(focus.buf)) then return nil end
  if focus.win and vim.api.nvim_win_is_valid(focus.win) then return focus.buf end
  if vim.fn.bufwinid(focus.buf) ~= -1 then return focus.buf end
end

function util.focused_win()
  local buf = focus_buf()
  local win = focus.win and vim.api.nvim_win_is_valid(focus.win) and focus.win or nil

  if win and (not buf or vim.api.nvim_win_get_buf(win) == buf) then return win end

  if buf then
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(candidate) == buf then return candidate end
    end
  end

  return win or vim.api.nvim_get_current_win()
end

function util.focused_buf()
  return focus_buf() or vim.api.nvim_win_get_buf(util.focused_win())
end

function util.focus_shown()
  return vim.api.nvim_win_get_buf(util.focused_win()) == util.focused_buf()
end

function util.focused_cursor()
  if util.focus_shown() then return vim.api.nvim_win_get_cursor(util.focused_win()) end

  local mark = vim.api.nvim_buf_get_mark(util.focused_buf(), '"')

  return mark[1] > 0 and mark or { 1, 0 }
end

function util.fail(message)
  error(message, 0)
end

function util.buf_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)

  return name ~= '' and name or nil
end

function util.buf_label(buf)
  return util.buf_path(buf) or ('bufnr ' .. buf)
end

function util.resolve(args, create)
  if args.bufnr then
    if not vim.api.nvim_buf_is_valid(args.bufnr) then util.fail('no buffer ' .. args.bufnr) end

    vim.fn.bufload(args.bufnr)

    return args.bufnr
  end

  if args.path then
    local path = vim.fs.normalize(vim.fn.fnamemodify(args.path, ':p'))
    local buf = vim.fn.bufnr(path)

    if buf == -1 then
      if not create and not vim.uv.fs_stat(path) then util.fail('no buffer or file: ' .. path) end

      buf = vim.fn.bufadd(path)
      vim.bo[buf].buflisted = true
    end

    vim.fn.bufload(buf)

    return buf
  end

  return util.focused_buf()
end

function util.break_undo(buf)
  Buffer(buf):break_undo()
end

function util.describe_buf(buf)
  return {
    bufnr = buf,
    path = util.buf_path(buf),
    filetype = vim.bo[buf].filetype,
    modified = vim.bo[buf].modified,
    line_count = vim.api.nvim_buf_line_count(buf),
  }
end

function util.locations(result)
  local out = {}

  if type(result) ~= 'table' then return out end

  if result.uri or result.targetUri then result = { result } end

  for _, loc in ipairs(result) do
    local uri = loc.uri or loc.targetUri
    local range = loc.range or loc.targetSelectionRange or loc.targetRange

    if uri and range then
      out[#out + 1] = { path = vim.uri_to_fname(uri), line = range.start.line + 1, col = range.start.character + 1 }
    end
  end

  return out
end

util.TARGET = {
  {
    name = 'path',
    type = schema.str({ description = 'File path. Omit both path and bufnr for the focused buffer.' }),
    optional = true,
  },
  { name = 'bufnr', type = schema.int(), optional = true },
}

util.POSITION = {
  { name = 'line', type = schema.int({ description = '1-based line.' }) },
  { name = 'col', type = schema.int({ description = '1-based column (default 1).' }), optional = true },
}

function util.params(...)
  local out = {}

  for _, list in ipairs({ ... }) do
    vim.list_extend(out, list)
  end

  return out
end

local function window_text(win, budget)
  local buf = vim.api.nvim_win_get_buf(win)
  local config = vim.api.nvim_win_get_config(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local first = vim.fn.line('w0', win)
  local last = vim.fn.line('w$', win)
  local name = vim.api.nvim_buf_get_name(buf)
  local head = string.format(
    'win %d%s%s: %s [%s%s] lines %d-%d of %d, cursor %d:%d',
    win,
    win == vim.api.nvim_get_current_win() and ' (current)' or '',
    config.relative ~= '' and ' float' or '',
    name ~= '' and compact.path(name)
      or ('[' .. (vim.bo[buf].buftype ~= '' and vim.bo[buf].buftype or 'No Name') .. ']'),
    vim.bo[buf].filetype,
    vim.bo[buf].modified and ', modified' or '',
    first,
    last,
    vim.api.nvim_buf_line_count(buf),
    cursor[1],
    cursor[2] + 1
  )
  local lines = {}

  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, first - 1, last, false)) do
    local lnum = first + i - 1

    lines[i] = string.format('%s%4d %s', lnum == cursor[1] and '>' or ' ', lnum, line)
  end

  return head .. '\n' .. compact.text(table.concat(lines, '\n'), budget)
end

function util.screen(budget_chars)
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local budget = math.floor((budget_chars or compact.BUDGET) / math.max(#wins, 1))
  local parts =
    { string.format('mode %s, tab %d of %d', vim.api.nvim_get_mode().mode, vim.fn.tabpagenr(), vim.fn.tabpagenr('$')) }

  for _, win in ipairs(wins) do
    parts[#parts + 1] = window_text(win, budget)
  end

  local open = require('surfaces').all()

  if #open > 0 then
    parts[#parts + 1] = 'surfaces: '
      .. table.concat(
        vim.tbl_map(function(s)
          return s.id .. ' ' .. s.kind
        end, open),
        ', '
      )
  end

  return table.concat(parts, '\n\n')
end

return util

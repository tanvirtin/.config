local Buffer = require('core.Buffer')
local Window = require('core.Window')
local buffers = require('core.buffers')
local editor = require('core.editor')
local fs = require('core.fs')
local compact = require('compact')
local schema = require('nvim_mcp.schema')

local util = {}

local focus = {}

function util.set_focus(win, buf)
  focus.win = win
  focus.buf = buf or (win and Window(win):is_valid() and Window(win):get_buffer().bufnr) or nil
end

local function focus_buf()
  if not (focus.buf and Buffer.exists(focus.buf)) then return nil end
  if focus.win and Window(focus.win):is_valid() then return focus.buf end
  if #Buffer(focus.buf):get_windows() > 0 then return focus.buf end
end

function util.focused_win()
  local buf = focus_buf()
  local win = focus.win and Window(focus.win):is_valid() and focus.win or nil

  if win and (not buf or Window(win):get_buffer().bufnr == buf) then return win end

  if buf then
    for _, candidate in ipairs(Window.list_tab()) do
      if candidate:get_buffer().bufnr == buf then return candidate.win_id end
    end
  end

  return win or Window.get_current().win_id
end

function util.focused_buf()
  return focus_buf() or Window(util.focused_win()):get_buffer().bufnr
end

function util.focus_shown()
  return Window(util.focused_win()):get_buffer().bufnr == util.focused_buf()
end

function util.focused_cursor()
  if util.focus_shown() then return Window(util.focused_win()):get_cursor() end

  local mark = Buffer(util.focused_buf()):get_mark('"')

  return mark[1] > 0 and mark or { 1, 0 }
end

function util.fail(message)
  error(message, 0)
end

function util.buf_path(buf)
  local name = Buffer(buf):get_name()

  return name ~= '' and name or nil
end

function util.buf_label(buf)
  return util.buf_path(buf) or ('bufnr ' .. buf)
end

function util.resolve(args, create)
  if args.bufnr then
    if not Buffer.exists(args.bufnr) then util.fail('no buffer ' .. args.bufnr) end

    Buffer(args.bufnr):load()

    return args.bufnr
  end

  if args.path then
    local path = fs.normalize(fs.full_path(args.path))
    local found = buffers.find(path)
    local buf = found and found.bufnr

    if not buf then
      if not create and not fs.exists(path) then util.fail('no buffer or file: ' .. path) end

      buf = buffers.add(path).bufnr
    end

    Buffer(buf):load()

    return buf
  end

  return util.focused_buf()
end

function util.break_undo(buf)
  Buffer(buf):break_undo()
end

function util.list(buf)
  Buffer(buf):set_listed(true)
end

function util.describe_buf(buf)
  local buffer = Buffer(buf)

  return {
    bufnr = buf,
    path = util.buf_path(buf),
    filetype = buffer:get_option('filetype'),
    modified = buffer:get_option('modified'),
    line_count = buffer:get_line_count(),
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
  local window = Window(win)
  local buffer = window:get_buffer()
  local config = window:get_config()
  local cursor = window:get_cursor()
  local top, last = window:get_visible_range()
  local first = top + 1
  local name = buffer:get_name()
  local head = string.format(
    'win %d%s%s: %s [%s%s] lines %d-%d of %d, cursor %d:%d',
    win,
    win == Window.get_current().win_id and ' (current)' or '',
    config.relative ~= '' and ' float' or '',
    name ~= '' and compact.path(name)
      or ('[' .. (buffer:get_option('buftype') ~= '' and buffer:get_option('buftype') or 'No Name') .. ']'),
    buffer:get_option('filetype'),
    buffer:get_option('modified') and ', modified' or '',
    first,
    last,
    buffer:get_line_count(),
    cursor[1],
    cursor[2] + 1
  )
  local lines = {}

  for i, line in ipairs(buffer:get_lines(first - 1, last)) do
    local lnum = first + i - 1

    lines[i] = string.format('%s%4d %s', lnum == cursor[1] and '>' or ' ', lnum, line)
  end

  return head .. '\n' .. compact.text(table.concat(lines, '\n'), budget)
end

function util.screen(budget_chars)
  local wins = Window.list_tab()
  local budget = math.floor((budget_chars or compact.BUDGET) / math.max(#wins, 1))
  local parts = { string.format('mode %s, tab %d of %d', editor.mode(), editor.tab_number(), editor.tab_count()) }

  for _, window in ipairs(wins) do
    parts[#parts + 1] = window_text(window.win_id, budget)
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

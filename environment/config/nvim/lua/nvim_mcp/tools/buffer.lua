local schema = require('nvim_mcp.schema')
local util = require('nvim_mcp.tools.util')

local MAX_READ_LINES = 2000

local function buffer_read(args)
  local buf = util.resolve(args)
  local total = vim.api.nvim_buf_line_count(buf)
  local first = math.max(args.start_line or 1, 1)
  local last = math.min(args.end_line or total, total, first + MAX_READ_LINES - 1)
  local out = {}

  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, first - 1, last, false)) do
    out[i] = string.format('%6d\t%s', first + i - 1, line)
  end

  local header = string.format(
    '%s (bufnr %d, lines %d-%d of %d%s)',
    util.buf_path(buf) or '[No Name]',
    buf,
    first,
    last,
    total,
    vim.bo[buf].modified and ', unsaved changes' or ''
  )

  return header .. '\n' .. table.concat(out, '\n')
end

local function treesitter_node(args)
  local buf = util.resolve(args)
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { args.line - 1, (args.col or 1) - 1 } })

  if not node then return vim.NIL end

  local srow, scol, erow, ecol = node:range()
  local parent = node:parent()

  return {
    type = node:type(),
    parent = parent and parent:type() or nil,
    start = { line = srow + 1, col = scol + 1 },
    ['end'] = { line = erow + 1, col = ecol + 1 },
  }
end

local function occurrences(text, needle)
  local found = {}
  local from = 1

  while true do
    local s, e = text:find(needle, from, true)

    if not s then break end

    found[#found + 1] = { s, e }
    from = e + 1
  end

  return found
end

local function line_of(text, offset)
  local _, newlines = text:sub(1, offset - 1):gsub('\n', '')

  return newlines + 1
end

local function buffer_edit(args)
  if args.old_string == '' then util.fail('old_string is empty; use buffer_write to replace a whole buffer') end
  if args.old_string == args.new_string then util.fail('old_string and new_string are identical') end

  local buf = util.resolve(args)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, '\n')
  local found = occurrences(text, args.old_string)

  if #found == 0 then util.fail('old_string not found in ' .. util.buf_label(buf)) end

  if #found > 1 and not args.replace_all then
    util.fail(string.format('old_string matches %d times; add surrounding context or set replace_all', #found))
  end

  local first = line_of(text, found[1][1])
  local last = line_of(text, found[#found][2])
  local span = table.concat(vim.list_slice(lines, first, last), '\n')
  local replaced = span:gsub(vim.pesc(args.old_string), (args.new_string:gsub('%%', '%%%%')))
  local new_lines = vim.split(replaced, '\n', { plain = true })

  util.break_undo(buf)
  vim.api.nvim_buf_set_lines(buf, first - 1, last, false, new_lines)

  return {
    path = util.buf_path(buf),
    bufnr = buf,
    replacements = #found,
    start_line = first,
    end_line = first + #new_lines - 1,
    saved = false,
  }
end

local function buffer_write(args)
  local buf = util.resolve(args, true)
  local new_lines = vim.split(args.content, '\n', { plain = true })

  if #new_lines > 1 and new_lines[#new_lines] == '' then new_lines[#new_lines] = nil end

  util.break_undo(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)

  return { path = util.buf_path(buf), bufnr = buf, line_count = #new_lines, saved = false }
end

local function buffer_save(args)
  local buf = util.resolve(args)

  if not util.buf_path(buf) then util.fail('bufnr ' .. buf .. ' has no file name to save to') end

  vim.api.nvim_buf_call(buf, function()
    vim.cmd('silent write ++p')
  end)

  return { path = util.buf_path(buf), bufnr = buf, saved = true }
end

return {
  {
    name = 'buffer_read',
    risk = 'read',
    summary = 'Read a buffer as numbered lines (1-based, inclusive), including unsaved changes. Prefer this over reading the file from disk.',
    params = util.params(util.TARGET, {
      { name = 'start_line', type = schema.int(), optional = true },
      { name = 'end_line', type = schema.int(), optional = true },
    }),
    fn = buffer_read,
  },
  {
    name = 'treesitter_node',
    risk = 'read',
    summary = 'Syntax node at a position: type, parent type, and its 1-based start and end.',
    params = util.params(util.TARGET, util.POSITION),
    fn = treesitter_node,
  },
  {
    name = 'buffer_edit',
    risk = 'write',
    summary = 'Replace an exact string in a buffer (like Edit, but on the live buffer). old_string must match once unless replace_all. One undo step; the buffer is left unsaved.',
    params = util.params(util.TARGET, {
      { name = 'old_string', type = schema.str() },
      { name = 'new_string', type = schema.str() },
      { name = 'replace_all', type = schema.bool(), optional = true },
    }),
    fn = buffer_edit,
  },
  {
    name = 'buffer_write',
    risk = 'write',
    summary = 'Replace a buffer\'s whole content, creating the buffer for a new path. One undo step; not saved.',
    params = util.params(util.TARGET, { { name = 'content', type = schema.str() } }),
    fn = buffer_write,
  },
  {
    name = 'buffer_save',
    risk = 'write',
    summary = 'Write a buffer to its file on disk, creating parent directories. Only when the user asked to save.',
    params = util.TARGET,
    fn = buffer_save,
  },
}

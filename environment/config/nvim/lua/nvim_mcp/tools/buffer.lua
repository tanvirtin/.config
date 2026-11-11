local Buffer = require('core.Buffer')
local compact = require('compact')
local fs = require('core.fs')
local outline = require('nvim_mcp.outline')
local schema = require('nvim_mcp.schema')
local util = require('nvim_mcp.tools.util')

local MAX_READ_LINES = 2000

local function shown(buf)
  local path = util.buf_path(buf)

  return path and fs.display(path) or ('bufnr ' .. buf)
end

local function definitions(buf)
  local buffer = Buffer(buf)
  local root = buffer:syntax_root()

  if not root then
    util.fail(
      string.format(
        'no syntax tree for %s (filetype "%s"); read it with buffer_read',
        shown(buf),
        buffer:get_option('filetype')
      )
    )
  end

  return outline.of(root, buf, buffer:get_lines())
end

local function symbol_span(buf, symbol)
  local found = outline.find(definitions(buf), symbol)

  if #found == 0 then
    util.fail(string.format('no definition of %s in %s; outline lists the ones it has', symbol, shown(buf)))
  end

  local others = {}

  for i = 2, #found do
    others[#others + 1] = found[i].first
  end

  return found[1].first, found[1].last, #others > 0 and ('; also defined at ' .. table.concat(others, ', ')) or ''
end

local function buffer_read(args)
  local buf = util.resolve(args)
  local buffer = Buffer(buf)
  local total = buffer:get_line_count()
  local from, to, note = args.start_line, args.end_line, ''

  if args.symbol then
    from, to, note = symbol_span(buf, args.symbol)
  end

  local first = math.max(from or 1, 1)
  local last = math.min(to or total, total, first + MAX_READ_LINES - 1)
  local out = {}

  for i, line in ipairs(buffer:get_lines(first - 1, last)) do
    out[i] = (first + i - 1) .. '\t' .. line
  end

  local path = util.buf_path(buf)
  local header = string.format(
    '%s (bufnr %d, lines %d-%d of %d%s%s)',
    path and fs.display(path) or '[No Name]',
    buf,
    first,
    last,
    total,
    buffer:get_option('modified') and ', unsaved changes' or '',
    note
  )

  return header .. '\n' .. table.concat(out, '\n')
end

local function buffer_outline(args, ctx)
  local buf = util.resolve(args)
  local entries = definitions(buf)
  local header = string.format('%s (%d lines)', shown(buf), Buffer(buf):get_line_count())
  local text = header .. '\n' .. compact.text(outline.format(entries), args.budget)

  return compact.reply(ctx.caller, entries, text)
end

local function treesitter_node(args)
  local buf = util.resolve(args)
  local node = Buffer(buf):node_at(args.line - 1, (args.col or 1) - 1)

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

local function report(ctx, diff)
  if ctx and ctx.edited and diff.path then ctx.edited(diff) end
end

local function substitute(text, edit, label)
  if edit.old_string == '' then util.fail('old_string is empty; use buffer_write to replace a whole buffer') end
  if edit.old_string == edit.new_string then util.fail('old_string and new_string are identical') end

  local found = occurrences(text, edit.old_string)

  if #found == 0 then util.fail('old_string not found in ' .. label) end

  if #found > 1 and not edit.replace_all then
    util.fail(string.format('old_string matches %d times; add surrounding context or set replace_all', #found))
  end

  local out, from = {}, 1

  for _, match in ipairs(found) do
    out[#out + 1] = text:sub(from, match[1] - 1)
    out[#out + 1] = edit.new_string
    from = match[2] + 1
  end

  out[#out + 1] = text:sub(from)

  return table.concat(out), #found
end

local function requested(args)
  local single = args.old_string ~= nil or args.new_string ~= nil

  if args.edits and single then util.fail('give old_string and new_string, or edits, not both') end
  if args.edits then
    if #args.edits == 0 then util.fail('edits is empty') end

    return args.edits, true
  end
  if not single then util.fail('give old_string and new_string, or a list of edits') end
  if args.old_string == nil or args.new_string == nil then util.fail('old_string and new_string go together') end

  return { { old_string = args.old_string, new_string = args.new_string, replace_all = args.replace_all } }, false
end

local function changed_span(old, new)
  local top = 0

  while top < #old and top < #new and old[top + 1] == new[top + 1] do
    top = top + 1
  end

  local bottom = 0

  while bottom < #old - top and bottom < #new - top and old[#old - bottom] == new[#new - bottom] do
    bottom = bottom + 1
  end

  return top, #old - bottom, vim.list_slice(new, top + 1, #new - bottom)
end

local function buffer_edit(args, ctx)
  local list, batch = requested(args)
  local buf = util.resolve(args)
  local lines = Buffer(buf):get_lines()
  local text = table.concat(lines, '\n')
  local label = util.buf_label(buf)
  local replacements = 0

  for index, item in ipairs(list) do
    local ok, result, count = pcall(substitute, text, item, label)

    if not ok then util.fail(batch and string.format('edit %d: %s', index, result) or result) end

    text, replacements = result, replacements + count
  end

  local new_lines = vim.split(text, '\n', { plain = true })
  local top, bottom, middle = changed_span(lines, new_lines)

  if bottom > top or #middle > 0 then
    util.break_undo(buf)
    util.list(buf)
    Buffer(buf):replace_lines(top, bottom, middle)
  end

  for _, item in ipairs(list) do
    report(ctx, { path = util.buf_path(buf), old = item.old_string, new = item.new_string })
  end

  local counts = { replacements .. (replacements == 1 and ' replacement' or ' replacements') }

  if batch then counts[#counts + 1] = #list .. (#list == 1 and ' edit' or ' edits') end

  return string.format(
    'edited %s lines %d-%d (%s), unsaved',
    shown(buf),
    top + 1,
    math.max(top + #middle, top + 1),
    table.concat(counts, ', ')
  )
end

local function buffer_write(args, ctx)
  local buf = util.resolve(args, true)
  local new_lines = vim.split(args.content, '\n', { plain = true })

  if #new_lines > 1 and new_lines[#new_lines] == '' then new_lines[#new_lines] = nil end

  local old = table.concat(Buffer(buf):get_lines(), '\n')

  util.break_undo(buf)
  util.list(buf)
  Buffer(buf):replace_lines(0, -1, new_lines)
  report(ctx, { path = util.buf_path(buf), old = old, new = table.concat(new_lines, '\n') })

  return string.format('wrote %s (bufnr %d, %d lines), unsaved', shown(buf), buf, #new_lines)
end

local function buffer_save(args)
  local buf = util.resolve(args)

  if not util.buf_path(buf) then util.fail('bufnr ' .. buf .. ' has no file name to save to') end

  Buffer(buf):write()

  return 'saved ' .. shown(buf)
end

return {
  {
    name = 'buffer_read',
    risk = 'read',
    summary = 'Read a buffer as numbered lines (1-based, inclusive), including unsaved changes. Prefer this over reading the file from disk. Give symbol to read one definition instead of the whole file.',
    params = util.params(util.TARGET, {
      { name = 'start_line', type = schema.int(), optional = true },
      { name = 'end_line', type = schema.int(), optional = true },
      {
        name = 'symbol',
        type = schema.str({ description = 'Name of a function, method, class or type: reads just its lines.' }),
        optional = true,
      },
    }),
    fn = buffer_read,
  },
  {
    name = 'outline',
    risk = 'read',
    summary = 'The definitions in a buffer (functions, methods, classes, types, markdown sections) with their line ranges, nested, from the syntax tree. Use it to find the part you need in a large file; skip it when you will read the whole file anyway.',
    params = util.params(util.TARGET, {
      { name = 'budget', type = schema.int({ description = 'Characters of output (default 6000).' }), optional = true },
    }),
    fn = buffer_outline,
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
    summary = 'Replace exact strings in a buffer, like Edit but on the live buffer. Give old_string and new_string, or edits for several at once (in order, all or none, one undo step). Each old_string must match once unless replace_all. Leaves the buffer unsaved.',
    params = util.params(util.TARGET, {
      { name = 'old_string', type = schema.str(), optional = true },
      { name = 'new_string', type = schema.str(), optional = true },
      { name = 'replace_all', type = schema.bool(), optional = true },
      {
        name = 'edits',
        type = schema.list(schema.model({
          { name = 'old_string', type = schema.str() },
          { name = 'new_string', type = schema.str() },
          { name = 'replace_all', type = schema.bool(), optional = true },
        })),
        optional = true,
      },
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
    summary = 'Write a buffer to its file on disk, creating parent directories. Only when the user asked to save, or before a command that reads the disk.',
    params = util.TARGET,
    fn = buffer_save,
  },
}

local lazy = require('core.lazy')

local fs = lazy('core.fs')
local Buffer = lazy('core.Buffer')
local Window = lazy('core.Window')
local buffers = lazy('core.buffers')
local content = lazy('harness.types.content')

local context = {}

context.TAG = 'editor-context'
context.INSTRUCTIONS = 'harness-instructions'

local function display_path(buffer)
  local name = buffer:get_name()

  return name ~= '' and fs.display(name) or '[No Name]'
end

function context.selection(buffer, range)
  local name = buffer:get_name()
  local source = name ~= '' and fs.display(name) or '[No Name]'

  return content.Attachment({
    label = string.format('%s:%s', source, range[1] == range[2] and range[1] or (range[1] .. '-' .. range[2])),
    source = source,
    path = name ~= '' and name or nil,
    range = { range[1], range[2] },
    lines = buffer:get_lines(range[1] - 1, range[2]),
    language = buffer:get_option('filetype'),
  })
end

local function describe(buffer, line, col, range)
  local parts = {
    string.format('The user is in %s (bufnr %d), line %d, col %d.', display_path(buffer), buffer.bufnr, line, col + 1),
  }

  if range then parts[#parts + 1] = string.format('They selected lines %d-%d.', range[1], range[2]) end

  parts[#parts + 1] = 'Editor tools default to this buffer when path and bufnr are omitted.'

  return content.context({
    where = string.format('<%s>%s</%s>', context.TAG, table.concat(parts, ' '), context.TAG),
    attachments = range and { context.selection(buffer, range) } or {},
  })
end

local TRAILING = '[,;:.!?%)%]]'

function context.absolute(path, dir)
  local expanded = fs.expand(path)

  if expanded:sub(1, 1) ~= '/' then expanded = fs.absolute_path(dir or fs.cwd(), expanded) end

  return fs.normalize(expanded)
end

function context.token(path, range)
  local source = fs.display(path)
  local span = range[1] == range[2] and tostring(range[1]) or (range[1] .. '-' .. range[2])

  if source:find('%s') then source = '"' .. source .. '"' end

  return '@' .. source .. ':' .. span
end

local function parse(token)
  local path, from, to = token:match('^@"([^"]+)":(%d+)%-(%d+)$')

  if not path then
    path, from = token:match('^@"([^"]+)":(%d+)$')
  end

  if not path then
    path, from, to = token:match('^@([^"]+):(%d+)%-(%d+)$')
  end

  if not path then
    path, from = token:match('^@([^"]+):(%d+)$')
  end

  if not path then
    path = token:match('^@"([^"]+)"$') or token:match('^@([^"]+)$')

    if path then return path, 1, math.huge, true end
  end

  if not path then return nil end

  from = tonumber(from)

  return path, from, tonumber(to) or from, false
end

local function candidates(path, dir)
  local expanded = fs.expand(path)

  if expanded:sub(1, 1) == '/' then return { expanded } end

  local out = { fs.absolute_path(fs.cwd(), expanded) }

  if dir and dir ~= '' then
    local from_dir = fs.absolute_path(dir, expanded)

    if from_dir ~= out[1] then out[2] = from_dir end
  end

  return out
end

local function token_attachment(token, dir, max_lines)
  local path, from, to, whole = parse(token)

  if not path then return nil end

  for _, full in ipairs(candidates(path, dir)) do
    local lines = buffers.lines_of(full)

    if #lines > 0 then
      if from < 1 or from > #lines then
        return nil, string.format('%s is past the end of the file, so it was sent as text', token)
      end

      to = math.min(math.max(to, from), #lines)

      local note

      if max_lines and to - from + 1 > max_lines then
        note = string.format('%s has %d lines; only the first %d were sent', token, to - from + 1, max_lines)
        to = from + max_lines - 1
      end

      return content.Attachment({
        token = token,
        label = token:sub(2),
        source = path,
        path = full,
        range = { from, to },
        lines = vim.list_slice(lines, from, to),
        language = fs.detect_filetype(full),
      }),
        note
    end
  end

  if whole then return nil end

  return nil, string.format('%s does not name a file, so it was sent as text', token)
end

local function next_token(text, at)
  local start = text:find('@', at, true)

  if not start then return nil end
  if start > 1 and not text:sub(start - 1, start - 1):match('[%s%(%[{"\'`]') then return '@', start + 1, start end

  local quoted = text:match('^@"[^"\n]+":%d+%-%d+', start)
    or text:match('^@"[^"\n]+":%d+', start)
    or text:match('^@"[^"\n]+"', start)

  if quoted then return quoted, start + #quoted, start end

  local plain = text:match('^@%S+', start)

  if not plain then return '@', start + 1, start end

  return (plain:gsub(TRAILING .. '+$', '')), start + #plain, start
end

function context.tokens(text)
  local out = {}
  local token, at, start = next_token(text, 1)

  while token do
    if parse(token) then out[#out + 1] = { token = token, start = start, finish = start + #token - 1 } end

    token, at, start = next_token(text, at)
  end

  return out
end

function context.names_file(token, dir)
  local path = parse(token)

  if not path then return false end

  for _, full in ipairs(candidates(path, dir)) do
    if buffers.find(full) or fs.exists(full) then return not fs.is_dir(full) end
  end

  return false
end

function context.resolve_tokens(text, dir, opts)
  opts = opts or {}
  local out, problems, seen = {}, {}, {}
  local token, at = next_token(text, 1)

  while token do
    if parse(token) and not seen[token] then
      seen[token] = true

      local attachment, problem = token_attachment(token, dir, opts.max_lines)

      if attachment then out[#out + 1] = attachment end
      if problem then problems[#problems + 1] = problem end
    end

    token, at = next_token(text, at)
  end

  return out, problems
end

local function echoed_limit(before, path, start)
  local limit

  for token in before:gmatch('@%S+') do
    local name, from, to = token:match('^@"?([^"]-)"?:(%d+)%-(%d+)')

    if name and tonumber(from) == start and context.absolute(name) == path then limit = tonumber(to) - start + 1 end
  end

  return limit or math.huge
end

function context.strip_echoed(text)
  if not text:find('\n%[/') and not text:find('^%[/') then return text end

  local lines = vim.split(text, '\n', { plain = true })
  local out = {}
  local i = 1

  while i <= #lines do
    local path, start = lines[i]:match('^%[(/.-):(%d+)%]$')

    if path then
      start = tonumber(start)

      local file = buffers.lines_of(path)
      local limit = echoed_limit(table.concat(out, '\n'), fs.normalize(path), start)
      local j, taken = i + 1, 0

      while j <= #lines and taken < limit and file[start + taken] ~= nil and lines[j] == file[start + taken] do
        j, taken = j + 1, taken + 1
      end

      i = j

      if lines[i] and lines[i]:match('^%s') and #out > 0 then
        out[#out] = out[#out] .. lines[i]
        i = i + 1
      end
    else
      out[#out + 1] = lines[i]
      i = i + 1
    end
  end

  return table.concat(out, '\n')
end

function context.capture(win, range)
  local window = Window(win)
  local cursor = window:get_cursor()

  return describe(window:get_buffer(), cursor[1], cursor[2], range)
end

function context.capture_buffer(buf, range)
  for _, window in ipairs(Window.list()) do
    if window:get_buffer().bufnr == buf then return context.capture(window.win_id, range) end
  end

  local buffer = Buffer(buf)
  local mark = buffer:get_mark('"')

  return describe(buffer, mark[1] > 0 and mark[1] or 1, mark[2], range)
end

function context.attach(captured, attachment)
  return content.attach(captured, attachment)
end

function context.instructions(text)
  return string.format('<%s>%s</%s>', context.INSTRUCTIONS, text, context.INSTRUCTIONS)
end

function context.strip(text)
  for _, name in ipairs({ context.INSTRUCTIONS, context.TAG }) do
    local tag = vim.pesc(name)

    text = text:gsub('<' .. tag .. '>.-</' .. tag .. '>%s*', '')
  end

  return text
end

function context.selections_in(text)
  local labels = {}

  local rest = text:gsub('Selected lines (%d+)%-(%d+) of (.-):\n(`+)[^\n]*\n.-\n%4%s*', function(from, to, where)
    labels[#labels + 1] = string.format('%s:%s', where, from == to and from or (from .. '-' .. to))
    return ''
  end)

  return rest, labels
end

return context

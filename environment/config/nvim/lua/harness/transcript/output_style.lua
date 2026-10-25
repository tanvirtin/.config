local output_style = {}

output_style.LABEL = 'output'

output_style.TERMINAL = 'terminal'

output_style.EXTENSIONS = {
  lua = 'lua',
  py = 'python',
  js = 'javascript',
  mjs = 'javascript',
  cjs = 'javascript',
  ts = 'typescript',
  tsx = 'tsx',
  jsx = 'javascript',
  json = 'json',
  jsonc = 'json',
  yaml = 'yaml',
  yml = 'yaml',
  toml = 'toml',
  sh = 'bash',
  bash = 'bash',
  zsh = 'bash',
  rs = 'rust',
  go = 'go',
  c = 'c',
  h = 'c',
  cpp = 'cpp',
  hpp = 'cpp',
  zig = 'zig',
  rb = 'ruby',
  java = 'java',
  kt = 'kotlin',
  swift = 'swift',
  css = 'css',
  html = 'html',
  xml = 'xml',
  sql = 'sql',
  vim = 'vim',
  diff = 'diff',
  patch = 'diff',
}

output_style.READERS = { cat = true, head = true, tail = true, bat = true, less = true, sed = true, nl = true }

output_style.DIFFS = {
  ['git diff'] = true,
  ['git show'] = true,
  ['git log -p'] = true,
  ['git stash show -p'] = true,
  diff = true,
}

output_style.FG = {}

for code = 30, 37 do
  output_style.FG[code] = code - 30
end

for code = 90, 97 do
  output_style.FG[code] = code - 82
end

local function last_segment(command)
  local segment = command

  for part in command:gmatch('[^|;&]+') do
    if part:match('%S') then segment = part end
  end

  return segment:gsub('^%s+', ''):gsub('%s+$', '')
end

local function first_segment(command)
  return (command:match('^[^|;&]*') or command):gsub('^%s+', ''):gsub('%s+$', '')
end

local function words(segment)
  local out = {}

  for word in segment:gmatch('%S+') do
    if not word:match('^%w+=') or #out > 0 then out[#out + 1] = word end
  end

  return out
end

local function extension_of(word)
  local ext = word:gsub('[\'"]', ''):match('%.([%w]+)$')

  return ext and output_style.EXTENSIONS[ext:lower()]
end

local function from_command(command)
  if not command or command == '' then return nil end

  local last = words(last_segment(command))
  local head = last[1]

  if not head then return nil end

  head = head:match('[^/]+$') or head

  if head == 'jq' then return 'json' end

  local lead = words(first_segment(command))

  for n = math.min(#lead, 4), 1, -1 do
    if output_style.DIFFS[table.concat(lead, ' ', 1, n)] then return 'diff' end
  end

  if output_style.READERS[head] then
    for i = #last, 2, -1 do
      local lang = extension_of(last[i])

      if lang then return lang end
    end
  end

  return nil
end

local function from_content(lines)
  local first

  for _, line in ipairs(lines) do
    if line:match('%S') then
      first = line
      break
    end
  end

  if not first then return nil end

  if first:match('^diff %-%-git ') or first:match('^@@ %-%d') or first:match('^%-%-%- %S') then return 'diff' end

  local opener = first:match('^%s*([%[{])')

  if not opener then return nil end

  for i = #lines, 1, -1 do
    local line = lines[i]

    if line:match('%S') then
      local closer = line:match('([%]}])%s*$')

      if closer and ((opener == '{' and closer == '}') or (opener == '[' and closer == ']')) then return 'json' end

      return nil
    end
  end

  return nil
end

function output_style.language(command, lines)
  return from_command(command) or from_content(lines)
end

function output_style.label(lang, family)
  local base = family or output_style.LABEL

  return lang and (base .. '_' .. lang) or base
end

local function apply_sgr(state, params)
  if params == '' then params = '0' end

  local codes = {}

  for code in params:gmatch('%d+') do
    codes[#codes + 1] = tonumber(code)
  end

  local i = 1

  while i <= #codes do
    local code = codes[i]

    if code == 0 then
      state.fg, state.bold = nil, nil
    elseif code == 1 then
      state.bold = true
    elseif code == 22 then
      state.bold = nil
    elseif code == 39 then
      state.fg = nil
    elseif output_style.FG[code] then
      state.fg = output_style.FG[code]
    elseif code == 38 and codes[i + 1] == 5 then
      local n = codes[i + 2]

      state.fg = n and n < 16 and n or nil
      i = i + 2
    elseif code == 38 and codes[i + 1] == 2 then
      state.fg = nil
      i = i + 4
    elseif code == 48 then
      i = i + (codes[i + 1] == 5 and 2 or codes[i + 1] == 2 and 4 or 0)
    end

    i = i + 1
  end
end

local function strip_line(line, row, spans, state)
  local out, from, col = {}, 1, 0

  local function emit(text)
    if text == '' then return end

    local start = col

    out[#out + 1] = text
    col = col + #text

    if state.fg then spans[#spans + 1] = { row, start, col, 'UiAnsi' .. state.fg } end
    if state.bold then spans[#spans + 1] = { row, start, col, 'UiAnsiBold' } end
  end

  while true do
    local at = line:find('\27', from, true)

    if not at then break end

    emit(line:sub(from, at - 1))

    local params, final, stop = line:match('^%[([%d;?]*)([%a@])()', at + 1)

    if params then
      if final == 'm' then apply_sgr(state, params) end
      from = stop
    else
      local osc_stop = line:match('^%].-\7()', at + 1) or line:match('^%].-\27\\()', at + 1)

      from = osc_stop or (at + 2)
    end
  end

  emit(line:sub(from))

  return table.concat(out)
end

function output_style.strip(lines)
  local spans, state, clean = {}, {}, nil

  for row, line in ipairs(lines) do
    if line:find('\27', 1, true) then
      clean = clean or { unpack(lines, 1, row - 1) }
      clean[row] = strip_line(line, row, spans, state)
    elseif clean then
      clean[row] = line

      if state.fg then spans[#spans + 1] = { row, 0, #line, 'UiAnsi' .. state.fg } end
      if state.bold then spans[#spans + 1] = { row, 0, #line, 'UiAnsiBold' } end
    end
  end

  if not clean then return lines, nil end

  return clean, #spans > 0 and spans or nil
end

output_style.ERRORS = {
  '^%s*error',
  '^%s*fatal',
  'error:',
  'Error:',
  'ERROR',
  'FAIL',
  '%f[%d][1-9]%d* failed',
  '^%s*failed',
  'Failed',
  'panic',
  'Traceback',
  'Exception',
  '✗',
  '✘',
  '^%s*E%s',
}

output_style.WARNINGS = { '^%s*warn', 'warning:', 'Warning:', 'WARN', 'deprecated', 'DEPRECATED' }

output_style.SUCCESS = { 'PASS', 'passed', '✓', '✔', '^ok ', '^ok$', 'Success', 'success', 'SUCCESS', '^%s*OK' }

output_style.STATUS = {
  ['?'] = 'UiAdded',
  A = 'UiAdded',
  D = 'UiRemoved',
  M = 'UiWarn',
  R = 'UiWarn',
  C = 'UiWarn',
  U = 'UiError',
}

local function any(line, patterns)
  for _, pattern in ipairs(patterns) do
    if line:find(pattern) then return true end
  end

  return false
end

local function line_rule(line)
  if any(line, output_style.ERRORS) then return 'UiError' end
  if any(line, output_style.WARNINGS) then return 'UiWarn' end
  if any(line, output_style.SUCCESS) then return 'UiAdded' end
end

local function status_rule(line, out)
  local x, y = line:match('^([ MADRCU?!])([ MADRCU?!]) %S')

  if not x or (x == ' ' and y == ' ') then return false end
  if (x == '?') ~= (y == '?') then return false end

  local group = output_style.STATUS[x ~= ' ' and x or y]

  if not group then return false end

  out[#out + 1] = { 0, 2, group }

  return true
end

local function path_rule(line, out)
  local from = 1

  while true do
    local start, stop = line:find('[%w%._%-/~]+%.%w+:%d+[:%d]*', from)

    if not start then return end

    out[#out + 1] = { start - 1, stop, 'UiPath' }
    from = stop + 1
  end
end

local memo, memo_size = {}, 0

output_style.MEMO_MAX = 4000

function output_style.rules(line)
  local cached = memo[line]

  if cached then return cached end

  local out = {}

  if line ~= '' then
    if not status_rule(line, out) then
      local group = line_rule(line)

      if group then out[#out + 1] = { 0, #line, group } end
    end

    path_rule(line, out)
  end

  if memo_size >= output_style.MEMO_MAX then
    memo, memo_size = {}, 0
  end

  memo[line], memo_size = out, memo_size + 1

  return out
end

return output_style

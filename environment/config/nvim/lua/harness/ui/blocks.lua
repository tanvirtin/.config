local Object = require('core.Object')
local compact = require('compact')
local context = require('harness.context')

local Block = Object:extend()

Block.KIND = {
  title = 'title',
  prompt = 'prompt',
  message = 'message',
  thought = 'thought',
  tool = 'tool',
  diff = 'diff',
  plan = 'plan',
  note = 'note',
  stop = 'stop',
}

Block.STATUS = {
  pending = 'pending',
  in_progress = 'in_progress',
  completed = 'completed',
  failed = 'failed',
}

Block.CATEGORY = {
  read = 'read',
  edit = 'edit',
  delete = 'delete',
  move = 'move',
  search = 'search',
  execute = 'execute',
  think = 'think',
  fetch = 'fetch',
  other = 'other',
}

Block.PREVIEW = 5
Block.OUTPUT_MAX = 200

function Block:constructor(kind, lines, fields)
  local block = { kind = kind, lines = lines }

  for key, value in pairs(fields or {}) do
    block[key] = value
  end

  return block
end

function Block:range()
  return self.start, self.finish
end

local blocks = { Block = Block }

local diff_text = (vim.text and vim.text.diff) or vim.diff

local function split(text)
  if not text:find('\n', 1, true) then return { text } end

  local lines, from = {}, 1

  while true do
    local at = text:find('\n', from, true)

    if not at then break end

    lines[#lines + 1] = text:sub(from, at - 1)
    from = at + 1
  end

  lines[#lines + 1] = text:sub(from)

  return lines
end

local function relative(path, dir)
  if type(path) ~= 'string' then return path end

  if dir and path:sub(1, #dir + 1) == dir .. '/' then return path:sub(#dir + 2) end

  return vim.fn.fnamemodify(path, ':~:.')
end

local function fence_marks(line)
  local marks, rest = line:match('^ ? ? ?(```+)(.*)$')

  if not marks then
    marks, rest = line:match('^ ? ? ?(~~~+)(.*)$')
  end

  return marks, rest
end

function blocks.fence_for(lines)
  local longest = 0

  for _, line in ipairs(lines) do
    local run = line:match('^ ? ? ?(`+)')

    if run and #run > longest then longest = #run end
  end

  return string.rep('`', math.max(3, longest + 1))
end

function blocks.fences(lines)
  local spans, open, start = {}, nil, nil

  for i, line in ipairs(lines) do
    local marks, rest = fence_marks(line)

    if marks then
      if not open then
        open, start = marks, i
      elseif marks:sub(1, 1) == open:sub(1, 1) and #marks >= #open and vim.trim(rest) == '' then
        spans[#spans + 1] = { start, i }
        open = nil
      end
    end
  end

  return spans, open and { start, nil, open } or nil
end

function blocks.fenced_at(lines, index)
  local spans, unclosed = blocks.fences(lines)

  if unclosed then spans[#spans + 1] = { unclosed[1], #lines + 1 } end

  for _, span in ipairs(spans) do
    if index > span[1] and index < span[2] then return span[1] + 1, span[2] - 1 end
  end
end

local function diff_lines(diff, dir)
  local old, new = diff.old, diff.new

  if old ~= '' and old:sub(-1) ~= '\n' then old = old .. '\n' end
  if new ~= '' and new:sub(-1) ~= '\n' then new = new .. '\n' end

  local body = split(vim.trim(diff_text(old, new, { ctxlen = 2 }) or ''))
  local fence = blocks.fence_for(body)
  local lines = { fence .. 'diff', '--- ' .. tostring(relative(diff.path, dir)) }

  vim.list_extend(lines, body)
  lines[#lines + 1] = fence

  return lines
end

local function diff_stats(lines)
  local added, removed = 0, 0

  for i = 3, #lines - 1 do
    local mark = lines[i]:sub(1, 1)

    if mark == '+' then
      added = added + 1
    elseif mark == '-' then
      removed = removed + 1
    end
  end

  return added, removed
end

local PLAN_MARK = { [Block.STATUS.completed] = 'x', [Block.STATUS.in_progress] = '~' }

local function plan_lines(entries)
  local lines = { '**plan**' }

  for _, entry in ipairs(entries) do
    lines[#lines + 1] = string.format('- [%s] %s', PLAN_MARK[entry.status] or ' ', entry.content)
  end

  return lines
end

local function quoted(text, prefix)
  local lines = prefix and { prefix } or {}

  for _, line in ipairs(split(text)) do
    lines[#lines + 1] = line == '' and '>' or '> ' .. line
  end

  return lines
end

local function flatten(items)
  local out = {}

  for _, item in ipairs(items) do
    for _, line in ipairs(split(item)) do
      out[#out + 1] = line
    end
  end

  return out
end

local function open_fence(lines)
  local _, unclosed = blocks.fences(lines)

  return unclosed and unclosed[3] or nil
end

local function tool_states(history, from, to)
  local states = {}

  for i = from, to do
    local event = history[i]

    if event.kind == 'tool_call' or event.kind == 'tool_update' then
      local state = states[event.id] or { started = i, input = {} }

      for _, key in ipairs({ 'title', 'name', 'category', 'status', 'locations', 'output' }) do
        if event[key] ~= nil then state[key] = event[key] end
      end

      if event.diffs and #event.diffs > 0 then state.diffs = event.diffs end

      for key, value in pairs(event.input or {}) do
        state.input[key] = value
      end

      if event.status == Block.STATUS.completed or event.status == Block.STATUS.failed then state.finished = i end

      states[event.id] = state
    end
  end

  return states
end

local function last_plans(history, from, to)
  local last, latest = {}, nil

  for i = from, to do
    local event = history[i]

    if event.kind == 'prompt' or event.kind == 'user' then
      if latest then last[latest] = true end
      latest = nil
    elseif event.kind == 'plan' then
      latest = i
    end
  end

  if latest then last[latest] = true end

  return last
end

local ARGUMENT_KEYS = {
  'command',
  'cmd',
  'file_path',
  'filePath',
  'absolute_path',
  'path',
  'pattern',
  'query',
  'url',
  'description',
  'code',
  'bufnr',
}

local function argument_text(key, value, dir)
  if type(value) == 'table' then
    local parts = {}

    for _, part in ipairs(value) do
      parts[#parts + 1] = tostring(part)
    end

    value = table.concat(parts, ' ')
  end

  value = tostring(value)

  return key:lower():find('path') and relative(value, dir) or value
end

local function tool_label(state, id, dir)
  local raw = state.name or (state.title and state.title:match('^(%S+)')) or 'tool'
  local name = raw
  local server, tool = name:match('^mcp__(.-)__(.+)$')

  if server then name = server .. ':' .. tool end

  local argument

  for _, key in ipairs(ARGUMENT_KEYS) do
    local value = state.input[key]

    if value ~= nil and value ~= vim.NIL and value ~= '' then
      argument = argument_text(key, value, dir)
      break
    end
  end

  if not argument and state.locations and state.locations[1] then argument = relative(state.locations[1].path, dir) end

  if not argument and state.title and state.title:find('%s') then
    argument = state.title:gsub('^' .. vim.pesc(raw) .. '%s*', '')
  end

  if not argument and not state.name and not state.title then argument = id end

  return compact.line(name, 80), argument and compact.line(argument, 200) or nil
end

local BODY = {
  [Block.CATEGORY.execute] = true,
  [Block.CATEGORY.search] = true,
  [Block.CATEGORY.fetch] = true,
  [Block.CATEGORY.other] = true,
}

local function output_lines(output)
  local lines = split(output:gsub('%s+$', ''))
  local hidden = #lines - Block.OUTPUT_MAX

  if hidden > 0 then
    lines = vim.list_slice(lines, 1, Block.OUTPUT_MAX)
    lines[#lines + 1] = string.format('… %d more lines', hidden)
  end

  return lines
end

local STOP_REASONS = {
  end_turn = 'Done',
  cancelled = 'Interrupted',
  max_tokens = 'Hit the token limit',
  max_turn_requests = 'Hit the turn limit',
  refusal = 'Refused',
}

blocks.STOP_REASONS = STOP_REASONS

local function build_turn(history, from, to, opts, last_turn)
  local times = opts.times or {}
  local list = {}
  local states = tool_states(history, from, to)
  local plans = last_plans(history, from, to)
  local diffs_shown = {}
  local turn = { tools = 0 }

  local opens = false

  local function add(kind, lines, fields)
    list[#list + 1] = Block(kind, lines, fields)

    if opens and kind ~= Block.KIND.prompt then
      list[#list].opens_reply = true
      opens = false
    end

    return list[#list]
  end

  local function stream(kind, text, i)
    local last = list[#list]

    if last and last.kind == kind then
      last.text = last.text .. text
      last.last_event = i
    else
      add(kind, {}, { text = text, first_event = i, last_event = i })
    end
  end

  local function show_diffs(id, tool)
    local state = states[id] or {}

    if diffs_shown[id] or not state.diffs then return end

    diffs_shown[id] = true

    for _, diff in ipairs(state.diffs) do
      local lines = diff_lines(diff, opts.dir)
      local added, removed = diff_stats(lines)

      add(Block.KIND.diff, lines, {
        id = id,
        path = diff.path,
        added = added,
        removed = removed,
        status = state.status,
      })

      if tool then
        tool.added = (tool.added or 0) + added
        tool.removed = (tool.removed or 0) + removed
      end
    end
  end

  local tools = {}

  local BUILD = {
    prompt = function(event, i)
      turn = { tools = 0, started = times[i] }
      add(Block.KIND.prompt, quoted(vim.trim(context.strip(event.text))), { first = i == 1 })
      opens = true
    end,
    message = function(event, i)
      stream(Block.KIND.message, event.text, i)
    end,
    thought = function(event, i)
      stream(Block.KIND.thought, event.text, i)
    end,
    tool_call = function(event)
      local state = states[event.id] or { input = {} }
      local name, argument = tool_label(state, event.id, opts.dir)
      local lines = { '-> ' .. name .. (argument and ' ' .. argument or '') }
      local category = state.category or Block.CATEGORY.other
      local folds = {}

      if opts.outputs ~= false and state.output and state.output ~= '' then
        if BODY[category] or state.status == Block.STATUS.failed then
          local body = output_lines(state.output)
          local fence = blocks.fence_for(body)

          lines[#lines + 1] = fence .. 'output'
          vim.list_extend(lines, body)
          lines[#lines + 1] = fence

          if #body > Block.PREVIEW + 1 then folds[1] = { 2 + Block.PREVIEW, #lines - 1 } end
        end
      end

      turn.tools = turn.tools + 1

      local tool = add(Block.KIND.tool, lines, {
        id = event.id,
        name = name,
        argument = argument,
        status = state.status,
        category = category,
        locations = state.locations,
        output = state.output,
        started = times[state.started],
        finished = state.finished and times[state.finished] or nil,
        folds = folds,
      })

      tools[event.id] = tool
      show_diffs(event.id, tool)
    end,
    tool_update = function(event)
      if event.status == Block.STATUS.failed and not tools[event.id] then
        add(Block.KIND.note, { '*failed:* `' .. compact.line(event.title or event.name or event.id, 200) .. '`' })
      end

      show_diffs(event.id, tools[event.id])
    end,
    plan = function(event, i)
      if plans[i] then add(Block.KIND.plan, plan_lines(event.entries)) end
    end,
    permission = function(event)
      if not event.allowed then add(Block.KIND.note, { '*refused:* `' .. compact.line(event.tool, 200) .. '`' }) end
    end,
    stop = function(event, i)
      local duration = turn.started and times[i] and times[i] - turn.started or nil

      add(Block.KIND.stop, { '*' .. tostring(event.reason) .. '*' }, {
        reason = event.reason,
        duration = duration,
        tools = turn.tools,
      })
    end,
    error = function(event)
      add(Block.KIND.note, flatten({ '**error:** ' .. event.message }), { error = true })
    end,
  }

  BUILD.user = BUILD.prompt

  for i = from, to do
    local event = history[i]

    if BUILD[event.kind] then BUILD[event.kind](event, i) end
  end

  for i, block in ipairs(list) do
    local tail = last_turn and i == #list

    if block.text then
      if block.kind == Block.KIND.thought then
        block.lines = quoted(block.text, '> [!thought]')
        block.folds = { { 1, #block.lines - 1 } }
        block.started = times[block.first_event]
        block.finished = times[block.last_event + 1]
        block.live = tail and opts.running or false
      else
        block.lines = split(block.text)
        local open = not tail and open_fence(block.lines)

        if open then block.lines[#block.lines + 1] = open end
      end

      block.text = nil
    else
      block.lines = flatten(block.lines)
    end
  end

  return list
end

local function turn_starts(history)
  local starts = { 1 }

  for i, event in ipairs(history) do
    if (event.kind == 'prompt' or event.kind == 'user') and i > 1 then starts[#starts + 1] = i end
  end

  return starts
end

function blocks.build(history, title, opts)
  opts = opts or {}

  local list = { Block(Block.KIND.title, { '# ' .. compact.line(title or 'Harness', 200) }) }
  local starts = turn_starts(history)
  local cache = opts.cache

  for n, from in ipairs(starts) do
    local to = (starts[n + 1] or #history + 1) - 1
    local last_turn = n == #starts
    local cached = cache and cache[from]
    local turn

    if cached and cached.to == to and not last_turn then
      turn = cached.blocks
    else
      turn = build_turn(history, from, to, opts, last_turn)
      if cache and not last_turn then cache[from] = { to = to, blocks = turn } end
    end

    vim.list_extend(list, turn)
  end

  return list
end

function blocks.lines(list)
  local out, n = {}, 0

  for i, block in ipairs(list) do
    block.start = n

    for _, line in ipairs(block.lines) do
      n = n + 1
      out[n] = line
    end

    local streaming = i == #list and block.kind == Block.KIND.message

    if not streaming then
      n = n + 1
      out[n] = ''
    end

    block.finish = n
  end

  return out
end

return blocks

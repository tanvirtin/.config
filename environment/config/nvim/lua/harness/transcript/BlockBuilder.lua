local Block = require('harness.transcript.Block')
local fences = require('harness.transcript.fences')
local tool_label = require('harness.transcript.tool_label')
local compact = require('compact')
local context = require('harness.context')
local EVENT = require('harness.events').KIND
local settings = require('harness.settings.transcript')

local blocks = { Block = Block, fence_for = fences.fence_for, fences = fences.fences, fenced_at = fences.fenced_at }

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

local function diff_lines(diff, dir)
  local old, new = diff.old, diff.new

  if old ~= '' and old:sub(-1) ~= '\n' then old = old .. '\n' end
  if new ~= '' and new:sub(-1) ~= '\n' then new = new .. '\n' end

  local body = split(vim.trim(diff_text(old, new, { ctxlen = 2 }) or ''))
  local fence = blocks.fence_for(body)
  local lines = { fence .. 'diff', '--- ' .. tostring(tool_label.relative(diff.path, dir)) }

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

local TOOL = { tool_call = true, tool_update = true }

local function tool_indices(history, from, to, updates)
  local indices, own = {}, {}

  for i = from, to do
    local event = history[i]

    if TOOL[event.kind] then indices[#indices + 1] = i end
    if event.kind == EVENT.tool_call then own[event.id] = true end
  end

  for id in pairs(own) do
    for _, i in ipairs(updates and updates[id] or {}) do
      if i > to then indices[#indices + 1] = i end
    end
  end

  table.sort(indices)

  return indices
end

local function tool_states(history, from, to, updates)
  local states = {}

  for _, i in ipairs(tool_indices(history, from, to, updates)) do
    local event = history[i]

    if TOOL[event.kind] then
      local state = states[event.id] or { started = i, input = {} }

      for _, key in ipairs({ 'title', 'name', 'category', 'status', 'locations', 'output' }) do
        if event[key] ~= nil then state[key] = event[key] end
      end

      if event.diffs and #event.diffs > 0 then state.diffs = event.diffs end
      state.parent = state.parent or event.parent

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

    if event.kind == EVENT.prompt or event.kind == EVENT.user then
      if latest then last[latest] = true end
      latest = nil
    elseif event.kind == EVENT.plan then
      latest = i
    end
  end

  if latest then last[latest] = true end

  return last
end

local BODY = {
  [Block.CATEGORY.execute] = true,
  [Block.CATEGORY.search] = true,
  [Block.CATEGORY.fetch] = true,
  [Block.CATEGORY.other] = true,
}

local function output_lines(output)
  local lines = split(output:gsub('%s+$', ''))
  local hidden = #lines - settings:get('output_max')

  if hidden > 0 then
    lines = vim.list_slice(lines, 1, settings:get('output_max'))
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

local function build_turn(history, from, to, opts, last_turn, updates)
  local times = opts.times or {}
  local list = {}
  local states = tool_states(history, from, to, updates)
  local plans = last_plans(history, from, to)
  local diffs_shown = {}
  local turn = { tools = 0 }

  local opens = false

  local function add(kind, lines, fields)
    list[#list + 1] = Block.make(kind, lines, fields)

    if opens and kind ~= Block.KIND.prompt then
      list[#list].opens_reply = true
      opens = false
    end

    return list[#list]
  end

  local function stream(kind, text, i, parent)
    local last = list[#list]

    if last and last.kind == kind and last.parent == parent then
      last.text = last.text .. text
      last.last_event = i
    else
      add(kind, {}, { text = text, first_event = i, last_event = i, parent = parent, depth = parent and 1 or nil })
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
        parent = state.parent,
        depth = state.parent and 1 or nil,
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
      if not event.steered then turn = { tools = 0, started = times[i] } end
      add(Block.KIND.prompt, quoted(vim.trim(context.strip(event.text))), { first = i == 1, steered = event.steered })
      opens = true
    end,
    message = function(event, i)
      stream(Block.KIND.message, event.text, i, event.parent)
    end,
    thought = function(event, i)
      stream(Block.KIND.thought, event.text, i, event.parent)
    end,
    tool_call = function(event)
      local state = states[event.id] or { input = {} }
      local name, argument = tool_label.label(state, event.id, opts.dir)
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

          if #body > settings:get('preview_lines') + 1 then
            folds[1] = { 2 + settings:get('preview_lines'), #lines - 1 }
          end
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
        parent = state.parent,
        depth = state.parent and 1 or nil,
      })

      if state.parent and tools[state.parent] then
        tools[state.parent].nested = (tools[state.parent].nested or 0) + 1
      end

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
        local open = not tail and fences.open(block.lines)

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
    if (event.kind == EVENT.prompt or event.kind == EVENT.user) and not event.steered and i > 1 then
      starts[#starts + 1] = i
    end
  end

  return starts
end

local function invalidate(history, cache, starts)
  local owners = cache.owners or {}

  cache.owners = owners

  for n, from in ipairs(starts) do
    local to = (starts[n + 1] or #history + 1) - 1

    if not cache[from] then
      for i = from, to do
        local event = history[i]

        if event.kind == EVENT.tool_call then
          owners[event.id] = from
        elseif event.kind == EVENT.tool_update and owners[event.id] and owners[event.id] ~= from then
          cache[owners[event.id]] = nil
        end
      end
    end
  end
end

function blocks.build(history, title, opts)
  opts = opts or {}

  local list = { Block.make(Block.KIND.title, { '# ' .. compact.line(title or 'Harness', 200) }) }
  local starts = turn_starts(history)
  local cache = opts.cache

  if cache then invalidate(history, cache, starts) end

  local updates = {}

  for i, event in ipairs(history) do
    if event.kind == EVENT.tool_update then
      updates[event.id] = updates[event.id] or {}
      table.insert(updates[event.id], i)
    end
  end

  local first = 1

  if opts.live_turns and #starts > opts.live_turns then
    first = #starts - opts.live_turns + 1
    list[#list + 1] = Block.make(
      Block.KIND.collapsed,
      { string.format('%d earlier turn%s · <CR> to show', first - 1, first == 2 and '' or 's') },
      { hidden = first - 1 }
    )
  end

  for n = first, #starts do
    local from = starts[n]
    local to = (starts[n + 1] or #history + 1) - 1
    local last_turn = n == #starts
    local cached = cache and cache[from]
    local turn

    if cached and cached.to == to and not last_turn then
      turn = cached.blocks
    else
      turn = build_turn(history, from, to, opts, last_turn, updates)
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

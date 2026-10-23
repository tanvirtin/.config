local compact = require('compact')
local fences = require('core.fences')
local context = require('harness.context')
local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')
local EVENT = require('harness.types.events').KIND
local keymaps = require('harness.settings.keymaps')
local settings = require('harness.settings.transcript')
local tool_label = require('harness.transcript.tool_label')
local EditLog = require('harness.edits.EditLog')

local blocks = { Block = Block, fence_for = fences.fence_for, fences = fences.fences, fenced_at = fences.fenced_at }

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

local FINISHED = { [Block.STATUS.completed] = true, [Block.STATUS.failed] = true }

local function diff_block(edit, path, text)
  local body = text and edit:text() or edit:patch().lines
  local fence = blocks.fence_for(body)
  local lines = { fence .. (text and 'diff' or 'edit'), '--- ' .. tostring(path) }

  vim.list_extend(lines, body)
  lines[#lines + 1] = fence

  return lines
end

local function plan_lines(entries)
  local lines, statuses = { 'plan' }, {}

  for i, entry in ipairs(entries) do
    lines[#lines + 1] = string.format('- [%s] %s', entry.status == Block.STATUS.completed and 'x' or ' ', entry.content)
    statuses[i] = entry.status or Block.STATUS.pending
  end

  return lines, statuses
end

local function quoted(text, prefix)
  local lines = prefix and { prefix } or {}

  for _, line in ipairs(split(text)) do
    lines[#lines + 1] = line == '' and '>' or '> ' .. line
  end

  return lines
end

local function indented(lines)
  local out = {}

  for i, line in ipairs(lines) do
    out[i] = line == '' and '' or '  ' .. line
  end

  return out
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

local function note_lines(label, detail)
  return flatten({ label .. ': ' .. detail })
end

local function label_of(name, dir)
  return (tool_label.label({ name = name, input = {} }, name, dir))
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
  cancelled = 'interrupted',
  max_tokens = 'hit the token limit',
  max_turn_requests = 'hit the turn limit',
  refusal = 'refused',
  error = 'failed',
}

blocks.STOP_REASONS = STOP_REASONS

local function build_turn(history, from, to, opts, last_turn, updates)
  local times = opts.times or {}
  local list = {}
  local states = tool_states(history, from, to, updates)
  local plans = last_plans(history, from, to)
  local diffs_shown = {}
  local turn = { tools = 0 }
  local edits = opts.edits or EditLog()
  local text = opts.outputs == false

  local function add(kind, lines, fields)
    list[#list + 1] = Block.make(kind, lines, fields)

    return list[#list]
  end

  local function stream(kind, text, i, parent, message_id)
    local last = list[#list]

    if last and last.kind == kind and last.parent == parent then
      last.text = last.text .. text
      last.last_event = i
      last.message_id = message_id or last.message_id
    else
      add(kind, {}, {
        text = text,
        first_event = i,
        last_event = i,
        parent = parent,
        depth = parent and 1 or nil,
        message_id = message_id,
      })
    end
  end

  local function show_diffs(id, tool)
    local state = states[id] or {}

    if diffs_shown[id] or not state.diffs then return end

    diffs_shown[id] = true

    for index, diff in ipairs(state.diffs) do
      local edit =
        edits:get(diff, id .. ':' .. index, FINISHED[state.status] == true, state.status == Block.STATUS.failed)
      local lines = diff_block(edit, tool_label.relative(diff.path, opts.dir), text)
      local patch = not text and edit:patch() or nil
      local stat = edit:stat()
      local added, removed = stat.added, stat.removed
      local last = list[#list]
      local preview = settings:get('diff_preview_lines')
      local folds = {}

      if patch and #patch.lines > preview + 1 then folds[1] = { Block.DIFF_HEADER + preview, #lines - 2 } end

      add(Block.KIND.diff, lines, {
        id = id,
        patch = patch and {
          rows = patch.rows,
          highlights = patch.highlights,
          words = patch.words,
          syntax = function()
            return edit:syntax()
          end,
        } or nil,
        whole = edit.whole,
        edit = edit.file,
        folds = folds,
        attached = last ~= nil and last.id == id and (last.kind == Block.KIND.tool or last.kind == Block.KIND.diff),
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
      local text, found = context.selections_in(context.strip(event.text))
      local selections = vim.list_extend(vim.deepcopy(event.selections or {}), found)
      local lines = quoted(vim.trim(text))

      for _, label in ipairs(selections) do
        lines[#lines + 1] = '> + ' .. label
      end

      add(Block.KIND.prompt, lines, {
        steered = event.steered,
        selections = #selections > 0 and #selections or nil,
        event = i,
      })
    end,
    message = function(event, i)
      stream(Block.KIND.message, event.text, i, event.parent, event.message_id)
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

          vim.list_extend(lines, fences.wrap(body, 'output'))

          if #body > settings:get('preview_lines') + 1 then
            folds[1] = { 2 + settings:get('preview_lines'), #lines - 2 }
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
        add(Block.KIND.note, note_lines('failed', compact.line(event.title or event.name or event.id, 200)), {
          label = 'failed',
        })
      end

      show_diffs(event.id, tools[event.id])
    end,
    plan = function(event, i)
      if plans[i] then
        local lines, statuses = plan_lines(event.entries)
        add(Block.KIND.plan, lines, { statuses = statuses })
      end
    end,
    permission = function(event)
      if event.allowed then return end

      local tool = event.id and tools[event.id]
      local outcome = event.cancelled and 'cancelled' or 'refused'

      if tool then
        tool.denied = outcome
      elseif not event.cancelled then
        add(Block.KIND.note, note_lines('refused', label_of(event.tool, opts.dir)), { label = 'refused' })
      end
    end,
    stop = function(event, i)
      local duration = turn.started and times[i] and times[i] - turn.started or nil
      local reason = event.reason or 'end_turn'

      turn.stopped = true
      add(Block.KIND.stop, { '*' .. reason .. '*' }, {
        reason = reason,
        duration = duration,
        tools = turn.tools,
      })
    end,
    error = function(event)
      add(Block.KIND.note, note_lines('error', event.message), { label = 'error' })
    end,
  }

  BUILD.user = BUILD.prompt

  for i = from, to do
    local event = history[i]

    if BUILD[event.kind] then BUILD[event.kind](event, i) end
  end

  local ended = turn.stopped or not last_turn

  for i, block in ipairs(list) do
    local tail = last_turn and i == #list

    if ended and block.kind == Block.KIND.tool and not FINISHED[block.status] then block.interrupted = true end

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

      if block.depth then
        block.lines = indented(block.lines)
        block.indented = true
      end
    else
      block.lines = flatten(block.lines)
    end
  end

  return blocks.nest(list, times)
end

local function last_activity(block, times)
  return block.finished
    or (block.last_event and times[block.last_event + 1] or times[block.last_event])
    or block.started
end

function blocks.nest(list, times)
  local owners, children = {}, {}

  for _, block in ipairs(list) do
    if block.kind == Block.KIND.tool and block.id and not block.parent then owners[block.id] = true end
  end

  for _, block in ipairs(list) do
    if block.parent and owners[block.parent] then
      children[block.parent] = children[block.parent] or {}
      table.insert(children[block.parent], block)
    end
  end

  if not next(children) then return list end

  local out = {}

  for _, block in ipairs(list) do
    if not (block.parent and owners[block.parent]) then
      out[#out + 1] = block

      if block.kind == Block.KIND.tool and children[block.id] then
        for _, child in ipairs(children[block.id]) do
          local at = times and last_activity(child, times)

          if at and block.finished and at > block.finished then block.finished = at end
        end

        for i, child in ipairs(children[block.id]) do
          child.first_child = i == 1 or nil
          child.last_child = i == #children[block.id] or nil
        end

        vim.list_extend(out, children[block.id])
      end
    end
  end

  return out
end

local GROUPABLE = { [Block.CATEGORY.read] = 'file', [Block.CATEGORY.search] = 'pattern' }
local GROUP_VERB = { [Block.CATEGORY.read] = 'Read', [Block.CATEGORY.search] = 'Searched' }

local function groupable(block)
  return block.kind == Block.KIND.tool
    and not block.parent
    and block.status == Block.STATUS.completed
    and GROUPABLE[block.category] ~= nil
end

local function group_label(run)
  local counts, order = {}, {}

  for _, block in ipairs(run) do
    if not counts[block.category] then order[#order + 1] = block.category end
    counts[block.category] = (counts[block.category] or 0) + 1
  end

  local parts = {}

  for i, category in ipairs(order) do
    local verb = GROUP_VERB[category]
    parts[#parts + 1] = (i == 1 and verb or verb:lower()) .. ' ' .. theme.plural(counts[category], GROUPABLE[category])
  end

  return table.concat(parts, ', ')
end

local function make_group(run)
  local label = group_label(run)
  local id = 'group:' .. (run[1].id or '')
  local header = Block.make(Block.KIND.tool, { '-> ' .. label }, {
    id = id,
    name = label,
    status = Block.STATUS.completed,
    category = run[1].category,
    grouped = #run,
    started = run[1].started,
    finished = run[#run].finished,
    folds = {},
  })

  for i, block in ipairs(run) do
    block.parent = id
    block.depth = 1
    block.first_child = i == 1 or nil
    block.last_child = i == #run or nil
  end

  return header
end

function blocks.group(list, live)
  local out, run = {}, {}

  local function flush(at_end)
    if #run >= 2 and not (at_end and live) then out[#out + 1] = make_group(run) end

    vim.list_extend(out, run)
    run = {}
  end

  for _, block in ipairs(list) do
    if groupable(block) then
      run[#run + 1] = block
    else
      flush(false)
      out[#out + 1] = block
    end
  end

  flush(true)

  return out
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

local ROW = { [Block.KIND.tool] = true, [Block.KIND.diff] = true }

function blocks.tighten(list)
  for i, block in ipairs(list) do
    local after = list[i + 1]
    local tight = after ~= nil
      and ((ROW[after.kind] and (ROW[block.kind] or block.depth ~= nil)) or (ROW[block.kind] and after.depth ~= nil))

    block.tight = tight or nil
  end

  return list
end

function blocks.build(history, title, opts)
  opts = opts or {}

  local list = { Block.make(Block.KIND.title, { '# ' .. compact.line(title or 'untitled', 200) }) }
  local starts = turn_starts(history)
  local cache = opts.cache

  if cache then invalidate(history, cache, starts) end
  if opts.edits then opts.edits:prime(history) end

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
    list[#list + 1] = Block.make(Block.KIND.collapsed, {
      string.format(
        '%d earlier turn%s · %s to show',
        first - 1,
        first == 2 and '' or 's',
        keymaps:get('transcript').activate
      ),
    })
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
      if opts.groups then turn = blocks.group(turn, last_turn and opts.running) end
      if cache and not last_turn then cache[from] = { to = to, blocks = turn } end
    end

    vim.list_extend(list, turn)
  end

  return blocks.tighten(list)
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

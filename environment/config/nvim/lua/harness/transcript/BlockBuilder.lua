local compact = require('compact')
local Object = require('core.Object')
local fences = require('core.fences')
local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')
local EVENT = require('harness.types.events').KIND
local keymaps = require('harness.settings.keymaps')
local TurnBuilder = require('harness.transcript.TurnBuilder')

local BlockBuilder = Object:extend()

BlockBuilder.Block = Block
BlockBuilder.fence_for = fences.fence_for
BlockBuilder.fences = fences.fences
BlockBuilder.fenced_at = fences.fenced_at

BlockBuilder.STOP_REASONS = {
  cancelled = 'interrupted',
  max_tokens = 'hit the token limit',
  max_turn_requests = 'hit the turn limit',
  refusal = 'refused',
  error = 'failed',
}

BlockBuilder.GROUPABLE = { [Block.CATEGORY.read] = 'file', [Block.CATEGORY.search] = 'pattern' }

BlockBuilder.GROUP_VERB = { [Block.CATEGORY.read] = 'Read', [Block.CATEGORY.search] = 'Searched' }

BlockBuilder.ROW = { [Block.KIND.tool] = true, [Block.KIND.diff] = true }

function BlockBuilder:constructor(opts)
  return { opts = opts or {} }
end

function BlockBuilder.last_activity(block, times)
  return block.finished
    or (block.last_event and times[block.last_event + 1] or times[block.last_event])
    or block.started
end

function BlockBuilder.nest(list, times)
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
          local at = times and BlockBuilder.last_activity(child, times)

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

function BlockBuilder.groupable(block)
  return block.kind == Block.KIND.tool
    and not block.parent
    and block.status == Block.STATUS.completed
    and BlockBuilder.GROUPABLE[block.category] ~= nil
end

function BlockBuilder.group_label(run)
  local counts, order = {}, {}

  for _, block in ipairs(run) do
    if not counts[block.category] then order[#order + 1] = block.category end
    counts[block.category] = (counts[block.category] or 0) + 1
  end

  local parts = {}

  for i, category in ipairs(order) do
    local verb = BlockBuilder.GROUP_VERB[category]

    parts[#parts + 1] = (i == 1 and verb or verb:lower())
      .. ' '
      .. theme.plural(counts[category], BlockBuilder.GROUPABLE[category])
  end

  return table.concat(parts, ', ')
end

function BlockBuilder.make_group(run)
  local label = BlockBuilder.group_label(run)
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

function BlockBuilder.group(list, live)
  local out, run = {}, {}

  local function flush(at_end)
    if #run >= 2 and not (at_end and live) then out[#out + 1] = BlockBuilder.make_group(run) end

    vim.list_extend(out, run)
    run = {}
  end

  for _, block in ipairs(list) do
    if BlockBuilder.groupable(block) then
      run[#run + 1] = block
    else
      flush(false)
      out[#out + 1] = block
    end
  end

  flush(true)

  return out
end

function BlockBuilder.tighten(list)
  local ROW = BlockBuilder.ROW

  for i, block in ipairs(list) do
    local after = list[i + 1]
    local tight = after ~= nil
      and ((ROW[after.kind] and (ROW[block.kind] or block.depth ~= nil)) or (ROW[block.kind] and after.depth ~= nil))

    block.tight = tight or nil
  end

  return list
end

function BlockBuilder.lines(list)
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

function BlockBuilder:_turn_starts(history)
  local starts = { 1 }

  for i, event in ipairs(history) do
    if (event.kind == EVENT.prompt or event.kind == EVENT.user) and not event.steered and i > 1 then
      starts[#starts + 1] = i
    end
  end

  return starts
end

function BlockBuilder:_invalidate(history, starts)
  local cache = self.opts.cache
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

  return self
end

function BlockBuilder:_updates(history)
  local updates = {}

  for i, event in ipairs(history) do
    if event.kind == EVENT.tool_update then
      updates[event.id] = updates[event.id] or {}
      table.insert(updates[event.id], i)
    end
  end

  return updates
end

function BlockBuilder:_collapsed(count)
  local label = string.format(
    '%d earlier turn%s · %s to show',
    count,
    count == 1 and '' or 's',
    keymaps:get('transcript').activate
  )

  return Block.make(Block.KIND.collapsed, { label })
end

function BlockBuilder:run(history, title)
  local opts = self.opts
  local list = { Block.make(Block.KIND.title, { '# ' .. compact.line(title or 'untitled', 200) }) }
  local starts = self:_turn_starts(history)
  local cache = opts.cache

  if cache then self:_invalidate(history, starts) end
  if opts.edits then opts.edits:prime(history) end

  local updates = self:_updates(history)
  local first = 1

  if opts.live_turns and #starts > opts.live_turns then
    first = #starts - opts.live_turns + 1
    list[#list + 1] = self:_collapsed(first - 1)
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
      local range = { from = from, to = to, last_turn = last_turn, updates = updates }

      turn = BlockBuilder.nest(TurnBuilder(history, range, opts):build(), opts.times or {})

      if opts.groups then turn = BlockBuilder.group(turn, last_turn and opts.running) end
      if cache and not last_turn then cache[from] = { to = to, blocks = turn } end
    end

    vim.list_extend(list, turn)
  end

  return BlockBuilder.tighten(list)
end

function BlockBuilder.build(history, title, opts)
  return BlockBuilder(opts):run(history, title)
end

return BlockBuilder

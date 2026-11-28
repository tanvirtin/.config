local Block = require('harness.transcript.model.Block')

local fleet = {}

fleet.VERBS = { new = true, prompt = true, read = true, list = true, cancel = true, close = true }

fleet.SETTLED = { [Block.STATUS.completed] = true, [Block.STATUS.failed] = true }

fleet.ROW = '   '

function fleet.verb(block)
  if block.kind ~= Block.KIND.tool or block.parent or block.grouped then return nil end

  for _, name in ipairs({ block.tool or '', block.name or '' }) do
    local verb = name:match('session_(%a+)$')

    if verb and fleet.VERBS[verb] then return verb end
  end
end

local function decoded(output)
  if type(output) ~= 'string' or output == '' then return nil end

  local ok, value = pcall(vim.json.decode, output)

  return ok and type(value) == 'table' and value or nil
end

local function text_of(value)
  return type(value) == 'string' and value ~= '' and value or nil
end

local function key_of(verb, block)
  local input = block.input or {}

  if verb == 'new' then
    local result = decoded(block.output)

    return result and text_of(result.session)
  end

  return text_of(input.session)
end

function fleet.members(run)
  local members, seen = {}, {}

  for _, block in ipairs(run) do
    local verb = fleet.verb(block)
    local key = verb and key_of(verb, block)

    if key and not seen[key] then
      local input = block.input or {}
      local member = { key = key, spawned = verb == 'new' or nil }

      if verb == 'new' then
        member.agent = text_of(input.agent)
        member.prompt = text_of(input.prompt)
      end

      seen[key] = member
      members[#members + 1] = member
    elseif key and verb == 'new' then
      local input = block.input or {}
      local member = seen[key]

      member.spawned = true
      member.agent = member.agent or text_of(input.agent)
      member.prompt = member.prompt or text_of(input.prompt)
    end
  end

  return members
end

function fleet.block(run)
  local members = fleet.members(run)
  local lines = { '-> fleet' }
  local settled = true
  local failed = false

  for _, member in ipairs(members) do
    lines[#lines + 1] = fleet.ROW .. member.key
  end

  for _, block in ipairs(run) do
    if not fleet.SETTLED[block.status] then settled = false end
    if block.status == Block.STATUS.failed then failed = true end
  end

  return Block.make(Block.KIND.fleet, lines, {
    id = 'fleet:' .. (run[1].id or ''),
    name = 'fleet',
    status = settled and (failed and Block.STATUS.failed or Block.STATUS.completed) or Block.STATUS.in_progress,
    members = members,
    started = run[1].started,
    finished = settled and run[#run].finished or nil,
    folds = #members > 0 and { { 1, #members } } or {},
  })
end

function fleet.gather(list)
  local run, first = {}, nil

  for i, block in ipairs(list) do
    local verb = fleet.verb(block)

    if verb and key_of(verb, block) then
      run[#run + 1] = block
      first = first or i
    end
  end

  if #run == 0 then return list end

  local out = {}
  local absorbed = {}

  for _, block in ipairs(run) do
    absorbed[block] = true
  end

  for i, block in ipairs(list) do
    if i == first then out[#out + 1] = fleet.block(run) end
    if not absorbed[block] then out[#out + 1] = block end
  end

  return out
end

function fleet.digest(block, snapshot)
  local parts = {}

  for _, member in ipairs(block.members or {}) do
    local live = snapshot and snapshot[member.key]

    parts[#parts + 1] = member.key .. '=' .. (live and live.digest or '-')
  end

  return table.concat(parts, ';')
end

return fleet

local compact = require('compact')
local dataclass = require('core.dataclass')
local events = require('harness.types.events')
local tool_label = require('harness.transcript.model.tool_label')

local K = events.KIND

local STATE = dataclass.enum({ 'starting', 'idle', 'working', 'waiting', 'done', 'failed', 'cancelled', 'gone' })

local STRING, NUMBER, TABLE = { type = 'string' }, { type = 'number' }, { type = 'table' }

local FleetMember = dataclass.define('FleetMember', {
  key = { type = 'string', required = true },
  state = { type = 'string', required = true, enum = STATE },
  agent = STRING,
  model = STRING,
  tool = STRING,
  result = STRING,
  ask = STRING,
  cost = NUMBER,
  started = NUMBER,
  finished = NUMBER,
  activity = TABLE,
  digest = STRING,
})

FleetMember.STATE = STATE

FleetMember.LIVE = { [STATE.starting] = true, [STATE.working] = true, [STATE.waiting] = true }

FleetMember.SETTLED = { [STATE.done] = true, [STATE.failed] = true, [STATE.cancelled] = true }

FleetMember.BUCKETS = 6

FleetMember.BUCKET_MS = 2000

FleetMember.RESULT_WIDTH = 60

local FAILED = { refusal = true, error = true, max_tokens = true, max_turn_requests = true }

local function scan(history)
  local found = { tools = {}, order = {} }

  for i = #history, 1, -1 do
    local event = history[i]

    if not event.parent then
      if event.kind == K.prompt or event.kind == K.user then
        found.prompt = found.prompt or i
        break
      elseif event.kind == K.stop and not found.stop then
        found.stop = i
      elseif event.kind == K.error and not found.error then
        found.error = i
      elseif event.kind == K.message and not found.message then
        found.message = i
      elseif events.TOOL[event.kind] and event.id then
        local state = found.tools[event.id]

        if not state then
          state = { input = {} }
          found.tools[event.id] = state
          table.insert(found.order, 1, event.id)
        end

        for _, field in ipairs({ 'name', 'title', 'status', 'locations' }) do
          if state[field] == nil and event[field] ~= nil then state[field] = event[field] end
        end

        if event.input then state.input = vim.tbl_extend('keep', state.input, event.input) end
      end
    end
  end

  return found
end

local function open_tool(found, dir)
  for i = #found.order, 1, -1 do
    local state = found.tools[found.order[i]]

    if not events.TOOL_FINISHED[state.status] then
      local name, argument = tool_label.label(state, found.order[i], dir)

      return argument and (name .. ' ' .. argument) or name
    end
  end
end

local function state_of(session, found)
  if session.state == 'closed' then return STATE.gone end
  if session.waiting and #session:waiting() > 0 then return STATE.waiting end
  if session:running() then return STATE.working end
  if not found.prompt then return STATE.idle end

  local stop = found.stop and session.history[found.stop]
  local reason = stop and stop.reason

  if reason == 'cancelled' then return STATE.cancelled end
  if found.error or FAILED[reason] then return STATE.failed end
  if stop then return STATE.done end

  return STATE.idle
end

local function activity(history, times, now)
  local buckets = {}

  for b = 1, FleetMember.BUCKETS do
    buckets[b] = 0
  end

  if not now then return buckets end

  local span = FleetMember.BUCKETS * FleetMember.BUCKET_MS

  for i = #history, 1, -1 do
    local at = times[i]

    if at and now - at >= span then break end

    local event = history[i]

    if at and event.kind == K.tool_call and not event.parent then
      local b = FleetMember.BUCKETS - math.floor((now - at) / FleetMember.BUCKET_MS)

      if b >= 1 then buckets[b] = buckets[b] + 1 end
    end
  end

  return buckets
end

local function result_of(session, found)
  local event = found.message and session.history[found.message]
  local text = event and event.text and vim.trim(event.text) or ''

  if text == '' then return nil end

  return compact.line((text:gsub('[*`]+', ''):gsub('%s+', ' ')), FleetMember.RESULT_WIDTH)
end

local function usage_cost(session)
  local usage = session.usage and session:usage()

  return usage and usage.cost or nil
end

local function model_of(session)
  local choice = session.choice and session:choice('model')

  return choice and (choice.name or choice.value) or nil
end

function FleetMember.of(session, now)
  local history = session.history or {}
  local times = session.times or {}
  local found = scan(history)
  local state = state_of(session, found)
  local settled = FleetMember.SETTLED[state]
  local waiting = state == STATE.waiting and session:waiting()[1] or nil

  local member = {
    key = session.key,
    state = state,
    agent = session.agent and session.agent.name or nil,
    model = model_of(session),
    tool = not settled and open_tool(found, session.dir) or nil,
    result = settled and result_of(session, found) or nil,
    ask = waiting and (waiting.title or waiting.tool) or nil,
    cost = usage_cost(session),
    started = found.prompt and times[found.prompt] or nil,
    finished = settled and found.stop and times[found.stop] or nil,
    activity = FleetMember.LIVE[state] and activity(history, times, now) or nil,
  }

  member.digest = table.concat({
    member.state,
    tostring(member.tool),
    tostring(member.result),
    tostring(member.ask),
    tostring(member.cost),
    tostring(member.model),
  }, '|')

  return FleetMember(member)
end

function FleetMember.starting(key)
  return FleetMember({ key = key, state = STATE.starting, digest = 'starting' })
end

function FleetMember.live(member)
  return member ~= nil and FleetMember.LIVE[member.state] == true
end

return FleetMember

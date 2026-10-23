local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')
local context = lazy('harness.context')
local events = lazy('harness.types.events')

local History = Object:extend()

History.RELATION = { behind = 'behind', extends = 'extends', diverged = 'diverged' }

function History:constructor()
  return { events = {}, times = {}, _shadow = nil }
end

local function stamp(events_list, times)
  times[#events_list] = times[#events_list] or Timer.now()
end

function History:append(event)
  local shadow = self._shadow

  if shadow then
    events.append(shadow.events, event)
    stamp(shadow.events, shadow.times)
    return false
  end

  events.append(self.events, event)
  stamp(self.events, self.times)

  return true
end

function History:last()
  return self.events[#self.events]
end

function History:begin_replay()
  self._shadow = { events = {}, times = {} }
end

function History:replaying()
  return self._shadow ~= nil
end

local USER = { [events.KIND.prompt] = true, [events.KIND.user] = true }
local LOCAL = { [events.KIND.stop] = true, [events.KIND.permission] = true, [events.KIND.error] = true }

local function prompts(list)
  local out = {}

  for i, event in ipairs(list) do
    if USER[event.kind] then out[#out + 1] = { index = i, text = vim.trim(context.strip(event.text or '')) } end
  end

  return out
end

local function compare(ours, theirs)
  for i = 1, math.min(#ours, #theirs) do
    if theirs[i].text ~= ours[i].text then return History.RELATION.diverged end
  end

  return #theirs < #ours and History.RELATION.behind or History.RELATION.extends
end

local function refreshable(list, from)
  if list[from].kind ~= events.KIND.user then return false end

  for i = from + 1, #list do
    if LOCAL[list[i].kind] then return false end
  end

  return true
end

local function replace(target, source)
  for i = #target, 1, -1 do
    target[i] = nil
  end

  for i, value in ipairs(source) do
    target[i] = value
  end
end

function History:_adopt(shadow)
  local list, times = self.events, self.times
  local ours, theirs = prompts(list), prompts(shadow.events)
  local relation = compare(ours, theirs)

  if relation == History.RELATION.behind then return nil end

  if relation == History.RELATION.extends then
    local last = ours[#ours]
    local from, source

    if last and refreshable(list, last.index) then
      from, source = last.index, theirs[#ours].index
    elseif #theirs > #ours then
      from, source = #list + 1, theirs[#ours + 1].index
    else
      return nil
    end

    local tail = vim.list_slice(shadow.events, source)

    if vim.deep_equal(tail, vim.list_slice(list, from)) then return nil end

    local now = Timer.now()

    for i = #list, from, -1 do
      list[i] = nil
    end

    for offset, event in ipairs(tail) do
      local index = from + offset - 1

      list[index] = event
      times[index] = times[index] or now
    end

    for i = #list + 1, #times do
      times[i] = nil
    end

    return events.NOTICE.appended
  end

  for i = 1, math.min(#list, #shadow.events) do
    shadow.times[i] = times[i] or shadow.times[i]
  end

  replace(list, shadow.events)
  replace(times, shadow.times)

  return events.NOTICE.reset
end

function History:end_replay(ok)
  local shadow = self._shadow

  self._shadow = nil

  if not ok or not shadow then return nil end

  return self:_adopt(shadow)
end

return History

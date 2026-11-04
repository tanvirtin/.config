local lazy = require('core.lazy')
local TurnIndex = require('harness.session.TurnIndex')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')
local context = lazy('harness.context')
local events = lazy('harness.types.events')

local History = Object:extend()

History.RELATION = { behind = 'behind', extends = 'extends', diverged = 'diverged' }

function History:constructor()
  return { events = {}, times = {}, turns = TurnIndex(), _shadow = nil }
end

function History:_stamp(events_list, times)
  times[#events_list] = times[#events_list] or Timer.now()
end

function History:append(event)
  local shadow = self._shadow

  if shadow then
    events.append(shadow.events, event)
    self:_stamp(shadow.events, shadow.times)
    return false
  end

  local before = #self.events

  events.append(self.events, event)
  self:_stamp(self.events, self.times)

  if #self.events > before then self.turns:add(self.events, #self.events) end

  return true
end

function History:reindex()
  self.turns:rebuild(self.events)

  return self
end

function History:last()
  return self.events[#self.events]
end

function History:turn_start()
  for i = #self.events, 1, -1 do
    if self.events[i].kind == events.KIND.prompt then return i end
  end

  return 1
end

function History:turn_tools()
  local list, by_id, order = self.events, {}, {}

  for i = #list, self:turn_start(), -1 do
    local event = list[i]

    if events.TOOL[event.kind] and event.id then
      local tool = by_id[event.id]

      if not tool then
        tool = { id = event.id }
        by_id[event.id] = tool
        order[#order + 1] = tool
      end

      if tool.status == nil and event.status then tool.status = event.status end
      if tool.diffs == nil and event.diffs and #event.diffs > 0 then tool.diffs = event.diffs end
    end
  end

  return order
end

function History:turn_asked()
  local list, asked = self.events, {}

  for i = #list, self:turn_start(), -1 do
    local event = list[i]

    if event.kind == events.KIND.permission and event.id then asked[event.id] = true end
  end

  return asked
end

function History:begin_replay()
  self._shadow = { events = {}, times = {} }
end

function History:replaying()
  return self._shadow ~= nil
end

local USER = { [events.KIND.prompt] = true, [events.KIND.user] = true }
local LOCAL = { [events.KIND.stop] = true, [events.KIND.permission] = true, [events.KIND.error] = true }

function History:_prompts(list)
  local out = {}

  for i, event in ipairs(list) do
    if USER[event.kind] then out[#out + 1] = { index = i, text = vim.trim(context.strip(event.text or '')) } end
  end

  return out
end

function History:_within(short, long)
  local at = 1

  for word in short:gmatch('%S+') do
    local found = long:find(word, at, true)

    if not found then return false end

    at = found + #word
  end

  return true
end

function History:_same_prompt(a, b)
  if a == b then return true end

  return #a <= #b and self:_within(a, b) or self:_within(b, a)
end

function History:_compare(ours, theirs)
  for i = 1, math.min(#ours, #theirs) do
    if not self:_same_prompt(ours[i].text, theirs[i].text) then return History.RELATION.diverged end
  end

  return #theirs < #ours and History.RELATION.behind or History.RELATION.extends
end

function History:_refreshable(list, from)
  if list[from].kind ~= events.KIND.user then return false end

  for i = from + 1, #list do
    if LOCAL[list[i].kind] then return false end
  end

  return true
end

function History:_settled(list, from)
  local out = {}

  for i = from + 1, #list do
    if not LOCAL[list[i].kind] then out[#out + 1] = list[i] end
  end

  return out
end

function History:_grown(ours, theirs)
  return events.TEXT[ours.kind]
    and theirs.kind == ours.kind
    and theirs.parent == ours.parent
    and type(theirs.text) == 'string'
    and #theirs.text > #ours.text
    and theirs.text:sub(1, #ours.text) == ours.text
end

function History:_later(ours, theirs)
  if #theirs < #ours then return nil end

  local extra = {}

  for i, event in ipairs(ours) do
    if not vim.deep_equal(event, theirs[i]) then
      if i < #ours or not self:_grown(event, theirs[i]) then return nil end

      local rest = vim.deepcopy(theirs[i])

      rest.text = theirs[i].text:sub(#event.text + 1)
      extra[#extra + 1] = rest
    end
  end

  for i = #ours + 1, #theirs do
    extra[#extra + 1] = theirs[i]
  end

  return #extra > 0 and extra or nil
end

function History:_replace(target, source)
  for i = #target, 1, -1 do
    target[i] = nil
  end

  for i, value in ipairs(source) do
    target[i] = value
  end
end

function History:_adopt(shadow)
  local list, times = self.events, self.times
  local ours, theirs = self:_prompts(list), self:_prompts(shadow.events)
  local relation = self:_compare(ours, theirs)

  if relation == History.RELATION.behind then return nil end

  if relation == History.RELATION.extends then
    local last = ours[#ours]
    local from, source

    if last and self:_refreshable(list, last.index) then
      from, source = last.index, theirs[#ours].index
    elseif #theirs > #ours then
      from, source = #list + 1, theirs[#ours + 1].index
    else
      local extra = self:_later(
        self:_settled(list, last and last.index or 0),
        self:_settled(shadow.events, last and theirs[#ours].index or 0)
      )

      if not extra then return nil end

      local now = Timer.now()

      for _, event in ipairs(extra) do
        list[#list + 1] = event
        times[#list] = now
      end

      return events.NOTICE.appended
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

  self:_replace(list, shadow.events)
  self:_replace(times, shadow.times)

  return events.NOTICE.reset
end

function History:end_replay(ok)
  local shadow = self._shadow

  self._shadow = nil

  if not ok or not shadow then return nil end

  local notice = self:_adopt(shadow)

  if notice then self:reindex() end

  return notice
end

return History

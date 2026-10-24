local Object = require('core.Object')
local EVENT = require('harness.types.events').KIND

local TurnIndex = Object:extend()

function TurnIndex:constructor()
  return { starts = { 1 }, updates = {}, homes = {}, late = {}, count = 0, epoch = 0 }
end

function TurnIndex:add(list, i)
  local event = list[i]
  local kind = event.kind

  if (kind == EVENT.prompt or kind == EVENT.user) and not event.steered and i > 1 then
    self.starts[#self.starts + 1] = i
  elseif kind == EVENT.tool_call then
    self.homes[event.id] = self.starts[#self.starts]
  elseif kind == EVENT.tool_update then
    local updates = self.updates[event.id]

    if not updates then
      updates = {}
      self.updates[event.id] = updates
    end

    updates[#updates + 1] = i

    local home = self.homes[event.id]

    if home and home ~= self.starts[#self.starts] then self.late[#self.late + 1] = home end
  end

  self.count = i

  return self
end

function TurnIndex:rebuild(list)
  self.starts, self.updates, self.homes, self.late = { 1 }, {}, {}, {}
  self.epoch = self.epoch + 1

  for i = 1, #list do
    self:add(list, i)
  end

  self.count = #list

  return self
end

function TurnIndex:fresh(list)
  return self.count == #list
end

function TurnIndex.of(list, index)
  if index and index:fresh(list) then return index end

  return TurnIndex():rebuild(list)
end

return TurnIndex

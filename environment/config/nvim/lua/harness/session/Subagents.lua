local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')
local events = lazy('harness.types.events')

local Subagents = Object:extend()

Subagents.FIELDS = { 'title', 'description', 'state', 'stop' }

Subagents.ACTIVE = { running = true, active = true, working = true, in_progress = true }

function Subagents:constructor(session)
  return { session = session, children = {}, seen = {} }
end

function Subagents:apply(event)
  local child = self.children[event.child]

  self.seen[event.child] = Timer.now()

  if not child then
    child = { id = event.child }
    self.children[event.child] = child
    self:_follow(child)
  end

  for _, key in ipairs(Subagents.FIELDS) do
    if event[key] ~= nil then child[key] = event[key] end
  end
end

function Subagents:_follow(child)
  local session = self.session

  if not (session.connection and session.connection.attach) then return end

  session.connection:attach(child.id, {
    event = function(event)
      self:_on_event(child, event)
    end,
    permission = function(request)
      return session.permissions:request(request)
    end,
  })
end

function Subagents:_on_event(child, event)
  local session = self.session

  if session.is_state_event(event) then return end

  self.seen[child.id] = Timer.now()

  if event.kind == events.KIND.delegation then
    child.tool = event.message or child.tool
    return session:_notify({ kind = events.KIND.subagent })
  end

  event.parent = event.parent or child.tool
  child.tool = child.tool or event.parent

  session:_handle(event)
end

function Subagents:summary(now)
  local active, quiet = 0, 0

  for id, child in pairs(self.children) do
    if child.tool and Subagents.ACTIVE[child.state] then
      active = active + 1
      quiet = math.max(quiet, (now or Timer.now()) - (self.seen[id] or now or Timer.now()))
    end
  end

  return { active = active, quiet = quiet }
end

function Subagents:detach_all()
  local connection = self.session.connection

  for id in pairs(self.children) do
    if connection.detach then connection:detach(id) end
  end
end

return Subagents

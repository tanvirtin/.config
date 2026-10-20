local lazy = require('core.lazy')

local Object = lazy('core.Object')
local events = lazy('harness.events')

local Subagents = Object:extend()

Subagents.FIELDS = { 'title', 'description', 'state', 'stop' }

function Subagents:constructor(session)
  return { session = session, children = {} }
end

function Subagents:apply(event)
  local child = self.children[event.child]

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
    update = function(update)
      self:_on_update(child, update)
    end,
    request = function(method, params)
      return session:_on_request(method, params)
    end,
  })
end

function Subagents:_on_update(child, update)
  local session = self.session
  local event = events.from_update(update)

  if not event or session.is_state_event(event) then return end

  if event.kind == events.KIND.delegation then
    child.tool = event.message or child.tool
    return session:_notify({ kind = events.KIND.subagent })
  end

  event.parent = event.parent or child.tool
  child.tool = child.tool or event.parent

  session:_handle(event)
end

function Subagents:detach_all()
  local connection = self.session.connection

  for id in pairs(self.children) do
    if connection.detach then connection:detach(id) end
  end
end

return Subagents

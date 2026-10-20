local lazy = require('core.lazy')

local Connection = lazy('harness.acp.connection')
local Object = lazy('core.Object')
local async = lazy('harness.async')
local events = lazy('harness.events')

local PermissionGate = Object:extend()

PermissionGate.METHOD = 'session/request_permission'

function PermissionGate:constructor(session)
  return { session = session, pending = {} }
end

local function kind_of(decision)
  if decision == true then return Connection.DECISION.allow_once end
  if type(decision) ~= 'string' then return Connection.DECISION.reject_once end

  return decision
end

function PermissionGate:request(params)
  local session = self.session
  local call = params.toolCall or {}
  local tool = events.tool_name(call) or call.title or ''
  local answer = async.Future.new()
  local pending = { tool = tool, answer = answer, id = call.toolCallId, title = call.title }

  local function decide(decision)
    if answer.done then return end

    self.pending[pending] = nil
    session:_notify({ kind = events.NOTICE.waiting })

    local kind = kind_of(decision)
    local allowed = kind:sub(1, 5) == 'allow'

    session:_record_permission(tool, allowed)
    session:_emit(events.permission(tool, allowed))
    answer:set_result({ outcome = Connection.permission_outcome(params.options, kind) })
  end

  self.pending[pending] = true
  session:_notify({ kind = events.NOTICE.waiting })

  local ok, decision = pcall(session.approve, { tool = tool, params = params, session = session })

  if not ok then
    decide(Connection.DECISION.reject_once)
  elseif type(decision) == 'table' and decision.on_complete then
    pending.dismiss = decision.dismiss
    decision:on_complete(function(err, kind)
      decide(not err and kind or Connection.DECISION.reject_once)
    end)
  else
    decide(decision)
  end

  return answer
end

function PermissionGate:waiting()
  local out = {}

  for pending in pairs(self.pending) do
    out[#out + 1] = { tool = pending.tool, id = pending.id, title = pending.title }
  end

  return out
end

function PermissionGate:cancel_all()
  for pending in pairs(self.pending) do
    self.pending[pending] = nil
    if pending.dismiss then pcall(pending.dismiss) end
    self.session:_emit(events.permission(pending.tool, false))
    pending.answer:set_result({ outcome = Connection.permission_outcome(nil, Connection.DECISION.cancelled) })
  end

  async.drain()
end

return PermissionGate

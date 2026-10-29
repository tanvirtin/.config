local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local events = lazy('harness.types.events')
local permission = require('harness.types.permission')

local DECISION = permission.DECISION

local PermissionGate = Object:extend()

function PermissionGate:constructor(session)
  return { session = session, pending = {} }
end

local function kind_of(decision)
  if decision == true then return DECISION.allow_once end
  if type(decision) ~= 'string' then return DECISION.reject_once end

  return decision
end

function PermissionGate:request(request)
  local session = self.session
  local tool = request.tool
  local answer = async.Future.new()
  local pending = { tool = tool, answer = answer, id = request.id, title = request.title }

  local function decide(decision)
    if answer.done then return end

    self.pending[pending] = nil
    session:_notify({ kind = events.NOTICE.waiting })

    local kind = kind_of(decision)
    local allowed = permission.allows(kind)

    session:_record_permission(tool, allowed)
    session:_emit(events.permission(tool, allowed, { id = pending.id }))
    answer:set_result(kind)
  end

  self.pending[pending] = true
  session:_notify({ kind = events.NOTICE.waiting })

  local ok, decision = pcall(session.approve, {
    tool = tool,
    id = request.id,
    title = request.title,
    input = request.input,
    choices = request.choices,
    session = session,
  })

  if not ok then
    decide(DECISION.reject_once)
  elseif type(decision) == 'table' and decision.on_complete then
    pending.dismiss = decision.dismiss
    decision:on_complete(function(err, kind)
      decide(not err and kind or DECISION.reject_once)
    end)
  else
    decide(decision)
  end

  return answer
end

function PermissionGate:waiting()
  local out = {}

  for pending in pairs(self.pending) do
    out[#out + 1] = { kind = events.ASK.permission, tool = pending.tool, id = pending.id, title = pending.title }
  end

  return out
end

function PermissionGate:cancel_all()
  for pending in pairs(self.pending) do
    self.pending[pending] = nil
    if pending.dismiss then pcall(pending.dismiss) end
    self.session:_emit(events.permission(pending.tool, false, { id = pending.id, cancelled = true }))
    pending.answer:set_result(DECISION.cancelled)
  end

  async.drain()
end

return PermissionGate

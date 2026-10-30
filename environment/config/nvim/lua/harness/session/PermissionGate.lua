local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local events = lazy('harness.types.events')
local permission = require('harness.types.permission')
local PermissionState = require('harness.session.PermissionState')

local DECISION = permission.DECISION

local PermissionGate = Object:extend()

function PermissionGate:constructor(session)
  return { session = session, pending = {}, state = PermissionState() }
end

local function label_of(choices, decision)
  for _, choice in ipairs(choices or {}) do
    if decision.option and choice.option == decision.option then return choice.label end
  end

  for _, choice in ipairs(choices or {}) do
    if choice.kind == decision.kind then return choice.label end
  end
end

function PermissionGate:request(request)
  local session = self.session
  local tool = request.tool
  local answer = async.Future.new()
  local pending = { tool = tool, answer = answer, id = request.id, title = request.title }

  local function decide(value)
    if answer.done then return end

    self.pending[pending] = nil
    session:_notify({ kind = events.NOTICE.waiting })

    local decision = permission.decision(value)
    local allowed = permission.allows(decision)

    self.state:record({
      tool = tool,
      kind = decision.kind,
      title = pending.title,
      label = label_of(request.choices, decision),
    })
    session:_notify({ kind = events.NOTICE.permissions })
    session:_record_permission(tool, allowed)
    session:_emit(events.permission(tool, allowed, { id = pending.id }))
    answer:set_result(decision)
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
    grants = self.state,
  })

  if not ok then
    decide(DECISION.reject_once)
  elseif type(decision) == 'table' and decision.on_complete then
    pending.dismiss = decision.dismiss
    decision:on_complete(function(err, value)
      decide(not err and value or DECISION.reject_once)
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
    self.state:record({ tool = pending.tool, kind = DECISION.cancelled, title = pending.title })
    self.session:_emit(events.permission(pending.tool, false, { id = pending.id, cancelled = true }))
    pending.answer:set_result(permission.decision(DECISION.cancelled))
  end

  async.drain()
end

function PermissionGate:grants()
  return self.state:grants()
end

function PermissionGate:revoke(tool)
  local revoked = self.state:revoke(tool)

  if revoked then self.session:_notify({ kind = events.NOTICE.permissions }) end

  return revoked
end

function PermissionGate:decisions()
  return self.state:decisions()
end

return PermissionGate

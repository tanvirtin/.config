local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local events = lazy('harness.types.events')
local elicitation = require('harness.types.elicitation')

local ElicitationGate = Object:extend()

function ElicitationGate:constructor(session)
  return { session = session, pending = {}, accepted = {} }
end

function ElicitationGate:request(request)
  local session = self.session
  local answer = async.Future.new()
  local pending = { request = request, answer = answer }

  function pending.settle(value, opts)
    if answer.done then return end

    self.pending[pending] = nil

    local result = elicitation.answer_of(value)

    if request.id and result.action == elicitation.ACTION.accept and not (opts and opts.completed) then
      self.accepted[request.id] = request
    end

    session:_notify({ kind = events.NOTICE.waiting })
    session:_emit(events.elicitation(request, result, opts))
    answer:set_result(result)
  end

  function answer.cancel()
    self:_close(pending, elicitation.cancel())
    async.drain()
  end

  self.pending[pending] = true
  session:_notify({ kind = events.NOTICE.waiting })

  if not session.elicit then
    pending.settle(elicitation.decline())
    return answer
  end

  local ok, value = pcall(session.elicit, { request = request, session = session })

  if not ok then
    pending.settle(elicitation.decline())
  elseif type(value) == 'table' and value.on_complete then
    pending.dismiss = value.dismiss
    value:on_complete(function(err, result)
      pending.settle(not err and result or elicitation.decline())
    end)
  else
    pending.settle(value)
  end

  return answer
end

function ElicitationGate:_close(pending, answer, opts)
  if not self.pending[pending] then return end

  local dismiss = pending.dismiss

  pending.dismiss = nil
  pending.settle(answer, opts)

  if dismiss then pcall(dismiss) end
end

function ElicitationGate:complete(id)
  for pending in pairs(self.pending) do
    if pending.request.id == id then return self:_close(pending, elicitation.accept(), { completed = true }) end
  end

  local request = self.accepted[id]

  if not request then return end

  self.accepted[id] = nil
  self.session:_emit(events.elicitation(request, elicitation.accept(), { completed = true }))
end

function ElicitationGate:waiting()
  local out = {}

  for pending in pairs(self.pending) do
    out[#out + 1] = { kind = events.ASK.elicitation, id = pending.request.tool, title = pending.request.message }
  end

  return out
end

function ElicitationGate:cancel_all()
  for pending in pairs(self.pending) do
    self:_close(pending, elicitation.cancel())
  end

  async.drain()
end

return ElicitationGate

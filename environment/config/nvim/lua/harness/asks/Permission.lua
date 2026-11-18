local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local permissions = lazy('harness.permissions')
local ASK = require('harness.types.events').ASK
local presenter = lazy('harness.asks.presenter')
local permission = require('harness.types.permission')

local Permission = Object:extend()

function Permission.ask(request)
  return presenter.present(request.session, Permission(request))
end

function Permission:constructor(request)
  return {
    kind = ASK.permission,
    session = request.session,
    future = async.Future(),
    text = permissions.describe(request),
    tool = request.tool,
    choices = permissions.choices(request),
  }
end

function Permission:is_open()
  return not self.future.done
end

function Permission:choice(key)
  for _, choice in ipairs(self.choices) do
    if choice.key == key or choice.kind == key then return choice end
  end
end

function Permission:answer(key)
  local chosen = self:choice(key)

  if not chosen then return false end

  self.future:set_result(permission.Decision({ kind = chosen.kind, option = chosen.option }))
  async.drain()

  return true
end

function Permission:dismiss()
  self.future:set_result(permission.decision(permission.DECISION.cancelled))
  async.drain()

  return self
end

return Permission

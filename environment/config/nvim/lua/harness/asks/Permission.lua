local lazy = require('core.lazy')

local Object = lazy('core.Object')
local async = lazy('harness.async')
local client = lazy('harness.client')
local ASK = require('harness.types.events').ASK
local presenter = lazy('harness.asks.presenter')
local permission = require('harness.types.permission')

local Permission = Object:extend()

function Permission.ask(request)
  return presenter.present(request.session, Permission(request))
end

Permission.FLEET_ALWAYS = 'Allow always (whole fleet)'

function Permission.choices_for(request)
  local choices = client.permission_choices(request)
  local session = request.session

  if not (session and session.parent) then return choices end

  return vim.tbl_map(function(choice)
    if choice.kind ~= permission.DECISION.allow_always or choice.option then return choice end

    return vim.tbl_extend('force', choice, { label = Permission.FLEET_ALWAYS })
  end, choices)
end

function Permission:constructor(request)
  return {
    kind = ASK.permission,
    session = request.session,
    future = async.Future(),
    text = client.describe_permission(request),
    tool = request.tool,
    choices = Permission.choices_for(request),
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

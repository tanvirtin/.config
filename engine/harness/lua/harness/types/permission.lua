local dataclass = require('core.dataclass')

local permission = {}

permission.DECISION = dataclass.enum({ 'allow_once', 'allow_always', 'reject_once', 'reject_always', 'cancelled' })

permission.Choice = dataclass.define('PermissionChoice', {
  kind = { type = 'string', required = true, enum = permission.DECISION },
  label = { type = 'string', required = true },
  option = { type = 'string' },
})

permission.Decision = dataclass.define('PermissionDecision', {
  kind = { type = 'string', required = true, enum = permission.DECISION },
  option = { type = 'string' },
})

permission.BEHAVIOR = dataclass.enum({ 'allow', 'deny', 'ask' })

permission.Rule = dataclass.define('PermissionRule', {
  text = { type = 'string', required = true },
  tool = { type = 'string', required = true },
  content = { type = 'string' },
  behavior = { type = 'string', required = true, enum = permission.BEHAVIOR },
  path = { type = 'string', required = true },
  format = { type = 'string', required = true },
})

permission.Grant = dataclass.define('PermissionGrant', {
  tool = { type = 'string', required = true },
  time = { type = 'number' },
})

permission.Entry = dataclass.define('PermissionEntry', {
  tool = { type = 'string', required = true },
  kind = { type = 'string', required = true, enum = permission.DECISION },
  title = { type = 'string' },
  label = { type = 'string' },
  time = { type = 'number' },
})

permission.Request = dataclass.define('PermissionRequest', {
  tool = { type = 'string', required = true },
  id = { type = 'string' },
  title = { type = 'string' },
  input = { type = 'table' },
  choices = {
    type = 'table',
    default = function()
      return {}
    end,
  },
})

function permission.decision(value)
  if permission.Decision.is(value) then return value end
  if value == true then return permission.Decision({ kind = permission.DECISION.allow_once }) end
  if type(value) == 'string' and dataclass.is_member(permission.DECISION, value) then
    return permission.Decision({ kind = value })
  end
  if type(value) == 'table' and dataclass.is_member(permission.DECISION, value.kind) then
    return permission.Decision({ kind = value.kind, option = value.option })
  end

  return permission.Decision({ kind = permission.DECISION.reject_once })
end

function permission.allows(decision)
  return permission.decision(decision).kind:sub(1, 5) == 'allow'
end

return permission

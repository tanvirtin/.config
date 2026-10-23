local dataclass = require('core.dataclass')

local permission = {}

permission.DECISION = dataclass.enum({ 'allow_once', 'allow_always', 'reject_once', 'reject_always', 'cancelled' })

function permission.allows(decision)
  return type(decision) == 'string' and decision:sub(1, 5) == 'allow'
end

return permission

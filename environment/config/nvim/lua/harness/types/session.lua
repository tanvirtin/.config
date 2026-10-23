local dataclass = require('core.dataclass')

local session = {}

session.Opened = dataclass.define('OpenedSession', {
  id = { type = 'string' },
  options = {
    type = 'table',
    default = function()
      return {}
    end,
  },
})

session.Stored = dataclass.define('StoredSession', {
  id = { type = 'string', required = true },
  title = { type = 'string' },
  updated_at = { type = 'string' },
})

return session

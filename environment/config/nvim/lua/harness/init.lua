local hub = require('harness.hub')
local permissions = require('harness.permissions')

local harness = {}

require('harness.tools').register()

harness.agent = require('harness.agent')
harness.hub = hub

harness.start = hub.start
harness.load = hub.load
harness.list = hub.list
harness.session = hub.session
harness.sessions = hub.sessions

function harness.setup(opts)
  hub.config = vim.tbl_extend('force', hub.config, { ask = permissions.ui_ask }, opts or {})

  require('harness.ui.commands').setup()
end

return harness

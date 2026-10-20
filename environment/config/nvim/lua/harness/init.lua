local hub = require('harness.hub')

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
  local ask = function(request)
    return require('harness.ui.transcript').ask(request)
  end

  hub.config = vim.tbl_extend('force', hub.config, { ask = ask }, opts or {})

  require('harness.features.EditCheckTime')():register_events()
  require('harness.ui.commands').setup()
end

return harness

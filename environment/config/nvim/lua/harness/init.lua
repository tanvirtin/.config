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

  local settings = require('harness.settings')
  local rest = settings.assign(opts)

  require('ui.hl').override(settings.theme:get('highlights'))

  hub.config = vim.tbl_extend('force', hub.config, { ask = ask }, rest)

  require('harness.features.EditCheckTime')():register_events()
  require('harness.cli.router').setup()
end

return harness

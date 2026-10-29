local lazy = require('core.lazy')

local hl = lazy('ui.hl')
local hub = lazy('harness.hub')
local tools = lazy('harness.tools')
local router = lazy('harness.cli.router')
local settings = lazy('harness.settings')
local composer = lazy('harness.ui.composer')
local transcript = lazy('harness.ui.transcript')
local SkillSync = lazy('harness.features.SkillSync')
local EditCheckTime = lazy('harness.features.EditCheckTime')

require('harness.transcript.content.builtin')()

local harness = {}

harness.agent = require('harness.agent')
harness.hub = hub

harness.start = hub.start
harness.load = hub.load
harness.list = hub.list
harness.session = hub.session
harness.sessions = hub.sessions

local features = {}

local function ask(request)
  return transcript.ask(request)
end

local function elicit(request)
  return transcript.elicit(request)
end

local function configure_settings(opts)
  local rest = settings.assign(opts)

  hl.override(settings.theme:get('highlights'))
  hub.config = vim.tbl_extend('force', hub.config, { ask = ask, elicit = elicit }, rest)
end

local function register_modules()
  tools.register()
  router.setup()
end

local function register_events()
  for _, feature in ipairs(features) do
    feature:cleanup()
  end

  features = { EditCheckTime():register_events(), SkillSync():register_events() }
  composer.register_events()
end

function harness.setup(opts)
  configure_settings(opts)
  register_modules()
  register_events()
end

return harness

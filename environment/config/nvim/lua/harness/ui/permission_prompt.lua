local lazy = require('core.lazy')

local asks = require('harness.ui.asks')
local ask_presenter = require('harness.ui.ask_presenter')
local PermissionPrompt = lazy('harness.ui.PermissionPrompt')

local permission_prompt = {}

permission_prompt.KEYS = asks.KEYS
permission_prompt.asks_of = asks.asks_of
permission_prompt.choice = asks.choice
permission_prompt.answer = asks.answer

function permission_prompt.ask(request)
  return ask_presenter.present(request.session, PermissionPrompt(request))
end

return permission_prompt

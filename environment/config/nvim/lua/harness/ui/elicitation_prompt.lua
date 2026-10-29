local lazy = require('core.lazy')

local ask_presenter = require('harness.ui.ask_presenter')
local ElicitationPrompt = lazy('harness.ui.ElicitationPrompt')

local elicitation_prompt = {}

function elicitation_prompt.ask(ask)
  return ask_presenter.present(ask.session, ElicitationPrompt(ask))
end

return elicitation_prompt

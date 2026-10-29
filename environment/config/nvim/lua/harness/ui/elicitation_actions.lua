local lazy = require('core.lazy')

local console = lazy('core.console')
local asks = require('harness.ui.asks')
local elicitation = require('harness.types.elicitation')

local elicitation_actions = {}

function elicitation_actions.pick(prompt)
  local field = prompt:current()

  if not field then return end

  local multi = field.kind == elicitation.FIELD.multi

  console.select(prompt:options(), {
    prompt = field.title or field.description or prompt.request.message,
    format_item = function(option)
      local checked = multi and (prompt:is_picked(option.value) and '[x] ' or '[ ] ') or ''

      return checked .. option.label .. (option.description and (' — ' .. option.description) or '')
    end,
  }, function(option)
    if option and prompt:is_open() then prompt:pick(option.value) end
    asks.changed(prompt.session)
  end)
end

function elicitation_actions.follow(view, prompt, action)
  if action == elicitation.CHOICE.write and view.composer then
    view.composer.open(view.session, { insert = true, display = view.display, answer = prompt })
  elseif action == elicitation.CHOICE.pick then
    elicitation_actions.pick(prompt)
  end

  asks.changed(view.session)
end

return elicitation_actions

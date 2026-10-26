local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local display = lazy('harness.ui.display')
local state = require('harness.ui.permission_state')
local NOTICE = require('harness.types.events').NOTICE
local PermissionPrompt = lazy('harness.ui.PermissionPrompt')

local permission_prompt = {}

permission_prompt.KEYS = state.KEYS
permission_prompt.asks_of = state.asks_of
permission_prompt.choice = state.choice
permission_prompt.answer = state.answer

local function refresh(session)
  Timer.schedule(function()
    session:_notify({ kind = NOTICE.waiting })
  end)
end

function permission_prompt.ask(request)
  local session = request.session
  local prompt = PermissionPrompt(request)
  local future = prompt.future

  state.add(session, prompt)

  function future.dismiss()
    prompt:dismiss()
  end

  future:on_complete(function()
    state.forget(session, prompt)
    refresh(session)
  end)

  Timer.schedule(function()
    if not display.buffer_of(session) then display.open(session, { background = true }) end
    session:_notify({ kind = NOTICE.waiting })
  end)

  return future
end

return permission_prompt

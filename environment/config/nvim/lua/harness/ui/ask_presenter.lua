local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local asks = require('harness.ui.asks')
local display = lazy('harness.ui.display')
local NOTICE = require('harness.types.events').NOTICE

local ask_presenter = {}

function ask_presenter.present(session, prompt)
  local future = prompt.future

  asks.add(session, prompt)

  function future.dismiss()
    prompt:dismiss()
  end

  future:on_complete(function()
    asks.forget(session, prompt)
    asks.changed(session)
  end)

  Timer.schedule(function()
    if not display.buffer_of(session) then display.open(session, { background = true }) end
    session:_notify({ kind = NOTICE.waiting })
  end)

  return future
end

return ask_presenter

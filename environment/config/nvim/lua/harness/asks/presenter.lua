local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local asks = require('harness.asks')
local client = lazy('harness.client')
local display = lazy('harness.ui.display')
local NOTICE = require('harness.types.events').NOTICE

local ask_presenter = {}

ask_presenter.MAX_HOPS = 8

function ask_presenter.holders(session)
  local holders, seen = { session }, { [session] = true }
  local key = session.parent

  for _ = 1, ask_presenter.MAX_HOPS do
    local parent = key and client.session(key)

    if not parent or seen[parent] then break end

    holders[#holders + 1] = parent
    seen[parent] = true
    key = parent.parent
  end

  return holders
end

function ask_presenter.present(session, prompt)
  local future = prompt.future
  local holders = ask_presenter.holders(session)

  for _, holder in ipairs(holders) do
    asks.add(holder, prompt)
  end

  function future.dismiss()
    prompt:dismiss()
  end

  future:on_complete(function()
    for _, holder in ipairs(holders) do
      asks.forget(holder, prompt)
      asks.changed(holder)
    end
  end)

  Timer.schedule(function()
    if not display.buffer_of(session) then display.open(session, { background = true }) end

    for _, holder in ipairs(holders) do
      client.notify(holder, { kind = NOTICE.waiting })
    end
  end)

  return future
end

return ask_presenter

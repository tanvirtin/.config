local lazy = require('core.lazy')

local DECISION = require('harness.acp.connection').DECISION
local NOTICE = require('harness.events').NOTICE
local Timer = require('core.Timer')

local async = lazy('harness.async')
local display = lazy('harness.ui.display')
local permissions = lazy('harness.permissions')

local permission_prompt = {}

permission_prompt.CHOICES = {
  { key = '1', kind = DECISION.allow_once, label = 'Allow once' },
  { key = '2', kind = DECISION.allow_always, label = 'Allow always (this session)' },
  { key = '3', kind = DECISION.reject_once, label = 'Reject' },
}

local asks = setmetatable({}, { __mode = 'k' })

function permission_prompt.asks_of(session)
  return vim.tbl_filter(function(ask)
    return not ask.future.done
  end, asks[session] or {})
end

local function refresh(session)
  Timer.schedule(function()
    session:_notify({ kind = NOTICE.waiting })
  end)
end

function permission_prompt.ask(request)
  local session = request.session
  local future = async.Future.new()
  local ask = { future = future, text = permissions.describe(request), tool = request.tool }

  asks[session] = asks[session] or {}
  table.insert(asks[session], ask)

  function future.dismiss()
    future:set_result(DECISION.cancelled)
    refresh(session)
  end

  future:on_complete(function()
    refresh(session)
  end)

  Timer.schedule(function()
    if not display.buffer_of(session) then display.open(session, { background = true }) end
    session:_notify({ kind = NOTICE.waiting })
  end)

  return future
end

function permission_prompt.answer(session, kind)
  local pending = permission_prompt.asks_of(session)[1]

  if not pending then return false end

  pending.future:set_result(kind)
  async.drain()

  return true
end

return permission_prompt

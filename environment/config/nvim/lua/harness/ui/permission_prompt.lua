local lazy = require('core.lazy')

local DECISION = require('harness.acp.connection').DECISION
local NOTICE = require('harness.events').NOTICE
local Timer = require('core.Timer')

local async = lazy('harness.async')
local display = lazy('harness.ui.display')
local permissions = lazy('harness.permissions')

local permission_prompt = {}

permission_prompt.KEYS = { '1', '2', '3', '4', '5', '6', '7', '8', '9' }

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
  local ask = {
    future = future,
    text = permissions.describe(request),
    tool = request.tool,
    choices = permissions.choices(request),
  }

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

function permission_prompt.choice(session, key)
  local pending = permission_prompt.asks_of(session)[1]

  for _, choice in ipairs(pending and pending.choices or {}) do
    if choice.key == key or choice.kind == key then return choice, pending end
  end
end

function permission_prompt.answer(session, key)
  local chosen, pending = permission_prompt.choice(session, key)

  if not chosen then return false end

  pending.future:set_result(chosen.kind)
  async.drain()

  return true
end

return permission_prompt

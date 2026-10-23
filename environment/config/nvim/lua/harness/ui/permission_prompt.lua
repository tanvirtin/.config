local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local display = lazy('harness.ui.display')
local NOTICE = require('harness.types.events').NOTICE
local PermissionPrompt = lazy('harness.ui.PermissionPrompt')

local permission_prompt = {}

permission_prompt.KEYS = { '1', '2', '3', '4', '5', '6', '7', '8', '9' }

local asks = setmetatable({}, { __mode = 'k' })

function permission_prompt.asks_of(session)
  return vim.tbl_filter(function(prompt)
    return prompt:is_open()
  end, asks[session] or {})
end

local function refresh(session)
  Timer.schedule(function()
    session:_notify({ kind = NOTICE.waiting })
  end)
end

function permission_prompt.ask(request)
  local session = request.session
  local prompt = PermissionPrompt(request)
  local future = prompt.future

  asks[session] = asks[session] or {}
  table.insert(asks[session], prompt)

  function future.dismiss()
    prompt:dismiss()
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

  return pending and pending:choice(key), pending
end

function permission_prompt.answer(session, key)
  local pending = permission_prompt.asks_of(session)[1]

  return pending ~= nil and pending:answer(key)
end

return permission_prompt

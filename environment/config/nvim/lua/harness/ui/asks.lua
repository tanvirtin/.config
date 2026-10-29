local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local NOTICE = require('harness.types.events').NOTICE

local asks = {}

asks.KEYS = { '1', '2', '3', '4', '5', '6', '7', '8', '9' }

local open = setmetatable({}, { __mode = 'k' })

function asks.asks_of(session)
  return vim.tbl_filter(function(prompt)
    return prompt:is_open()
  end, open[session] or {})
end

function asks.add(session, prompt)
  open[session] = open[session] or {}
  table.insert(open[session], prompt)

  return asks
end

function asks.forget(session, prompt)
  local list = open[session]

  if not list then return asks end

  for i, candidate in ipairs(list) do
    if candidate == prompt then
      table.remove(list, i)
      break
    end
  end

  if #list == 0 then open[session] = nil end

  return asks
end

function asks.first(session)
  return asks.asks_of(session)[1]
end

function asks.choice(session, key)
  local pending = asks.first(session)

  return pending and pending:choice(key), pending
end

function asks.answer(session, key)
  local pending = asks.first(session)

  if pending == nil then return false end

  return pending:answer(key), pending
end

function asks.changed(session)
  Timer.schedule(function()
    session:_notify({ kind = NOTICE.waiting })
  end)
end

return asks

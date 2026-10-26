local permission_state = {}

permission_state.KEYS = { '1', '2', '3', '4', '5', '6', '7', '8', '9' }

local asks = setmetatable({}, { __mode = 'k' })

function permission_state.asks_of(session)
  return vim.tbl_filter(function(prompt)
    return prompt:is_open()
  end, asks[session] or {})
end

function permission_state.add(session, prompt)
  asks[session] = asks[session] or {}
  table.insert(asks[session], prompt)

  return permission_state
end

function permission_state.forget(session, prompt)
  local list = asks[session]

  if not list then return permission_state end

  for i, candidate in ipairs(list) do
    if candidate == prompt then
      table.remove(list, i)
      break
    end
  end

  if #list == 0 then asks[session] = nil end

  return permission_state
end

function permission_state.choice(session, key)
  local pending = permission_state.asks_of(session)[1]

  return pending and pending:choice(key), pending
end

function permission_state.answer(session, key)
  local pending = permission_state.asks_of(session)[1]

  return pending ~= nil and pending:answer(key)
end

return permission_state

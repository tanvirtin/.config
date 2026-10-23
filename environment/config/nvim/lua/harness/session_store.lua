local lazy = require('core.lazy')

local event = lazy('core.event')
local console = lazy('core.console')
local dataclass = lazy('core.dataclass')

local session_store = {}

session_store.EVENT = require('core.dataclass').enum({ 'start', 'event', 'close' })
session_store.USER_EVENT = 'HarnessEvent'

local sessions = {}
local listeners = {}
local unsubscribes = {}

for name in pairs({ start = true, event = true, close = true }) do
  listeners[name] = {}
end

function session_store.on(names, callback)
  names = type(names) == 'table' and names or { names }

  local entries = {}

  for _, name in ipairs(names) do
    if not dataclass.is_member(session_store.EVENT, name) then
      error(string.format('unknown store event "%s"', tostring(name)), 2)
    end

    local entry = { fn = callback }

    table.insert(listeners[name], entry)
    entries[#entries + 1] = { name = name, entry = entry }
  end

  return function()
    for _, item in ipairs(entries) do
      for i, candidate in ipairs(listeners[item.name]) do
        if candidate == item.entry then table.remove(listeners[item.name], i) end
      end
    end
  end
end

function session_store.dispatch(name, session, payload)
  for _, entry in ipairs(vim.list_slice(listeners[name])) do
    local ok, err = pcall(entry.fn, session, payload)

    if not ok then console.warn(string.format('Harness: a %s listener failed: %s', name, tostring(err))) end
  end
end

function session_store.add(session)
  sessions[session.key] = session

  unsubscribes[session.key] = session:subscribe(function(update)
    session_store.dispatch(session_store.EVENT.event, session, update)
    pcall(event.emit, session_store.USER_EVENT, { session = session.key, kind = update.kind })
  end)

  session_store.dispatch(session_store.EVENT.start, session)

  return session
end

function session_store.remove(key)
  local session = sessions[key]

  if not session then return nil end

  sessions[key] = nil

  if unsubscribes[key] then
    unsubscribes[key]()
    unsubscribes[key] = nil
  end

  session_store.dispatch(session_store.EVENT.close, session)

  return session
end

function session_store.get(key)
  return sessions[key]
end

function session_store.each(callback)
  for _, session in pairs(sessions) do
    callback(session)
  end
end

function session_store.list(dir)
  local out = {}

  for _, session in pairs(sessions) do
    if session.state ~= 'closed' and (not dir or session.dir == dir) then out[#out + 1] = session end
  end

  table.sort(out, function(a, b)
    return tonumber(a.key:sub(2)) < tonumber(b.key:sub(2))
  end)

  return out
end

function session_store.clear()
  for key in pairs(sessions) do
    session_store.remove(key)
  end
end

return session_store

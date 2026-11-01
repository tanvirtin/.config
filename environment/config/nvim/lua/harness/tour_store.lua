local tour_store = {}

tour_store.EVENT = { start = 'start', stop = 'stop', update = 'update' }

tour_store.RECENT = 20

local current, recent, scopes, listeners = {}, {}, {}, {}

local function slot(session)
  if type(session) ~= 'string' or session == '' then error('a tour belongs to a session', 2) end

  return session
end

local function emit(kind, session, tour, opts)
  for _, listener in ipairs(vim.list_slice(listeners)) do
    listener(kind, session, tour, opts)
  end
end

function tour_store.start(session, tour, opts)
  session = slot(session)

  current[session] = tour

  local kept = recent[session] or {}

  recent[session] = kept
  table.insert(kept, 1, tour)
  kept[tour_store.RECENT + 1] = nil

  emit(tour_store.EVENT.start, session, tour, opts or {})

  return tour
end

function tour_store.stop(session)
  session = slot(session)

  local stopped = current[session]

  current[session], scopes[session] = nil, nil

  if stopped then emit(tour_store.EVENT.stop, session, stopped, {}) end

  return stopped
end

function tour_store.update(session, update)
  session = slot(session)

  local tour = current[session]

  if not tour then return false, 'no tour is running; start one with tour_start' end

  emit(tour_store.EVENT.update, session, tour, update)

  return true
end

function tour_store.set_scope(session, value)
  scopes[slot(session)] = value
end

function tour_store.scope(session)
  return scopes[slot(session)]
end

function tour_store.current(session)
  return current[slot(session)]
end

function tour_store.recent(session)
  return vim.list_slice(recent[slot(session)] or {})
end

function tour_store.on(listener)
  listeners[#listeners + 1] = listener

  return function()
    for index, existing in ipairs(listeners) do
      if existing == listener then
        table.remove(listeners, index)
        return
      end
    end
  end
end

function tour_store.reset()
  current, recent, scopes, listeners = {}, {}, {}, {}
end

return tour_store

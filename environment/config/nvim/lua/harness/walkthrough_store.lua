local walkthrough_store = {}

walkthrough_store.EVENT = { start = 'start', stop = 'stop', update = 'update', select = 'select' }

walkthrough_store.RECENT = 20

local current, recent, scopes, listeners = {}, {}, {}, {}

local function slot(session)
  if type(session) ~= 'string' or session == '' then error('a walkthrough belongs to a session', 2) end

  return session
end

local function emit(kind, session, walkthrough, opts)
  for _, listener in ipairs(vim.list_slice(listeners)) do
    listener(kind, session, walkthrough, opts)
  end
end

function walkthrough_store.start(session, walkthrough, opts)
  session = slot(session)

  current[session] = walkthrough

  local kept = recent[session] or {}

  recent[session] = kept
  table.insert(kept, 1, walkthrough)
  kept[walkthrough_store.RECENT + 1] = nil

  emit(walkthrough_store.EVENT.start, session, walkthrough, opts or {})

  return walkthrough
end

function walkthrough_store.stop(session)
  session = slot(session)

  local stopped = current[session]

  current[session], scopes[session] = nil, nil

  if stopped then emit(walkthrough_store.EVENT.stop, session, stopped, {}) end

  return stopped
end

function walkthrough_store.update(session, update)
  session = slot(session)

  local walkthrough = current[session]

  if not walkthrough then return false, 'no walkthrough is running; start one with walkthrough_start' end

  emit(walkthrough_store.EVENT.update, session, walkthrough, update)

  return true
end

function walkthrough_store.select(session, path, first, last)
  session = slot(session)

  if not current[session] then return false end

  emit(walkthrough_store.EVENT.select, session, current[session], { path = path, first = first, last = last })

  return true
end

function walkthrough_store.set_scope(session, value)
  scopes[slot(session)] = value
end

function walkthrough_store.scope(session)
  return scopes[slot(session)]
end

function walkthrough_store.current(session)
  return current[slot(session)]
end

function walkthrough_store.recent(session)
  return vim.list_slice(recent[slot(session)] or {})
end

function walkthrough_store.on(listener)
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

function walkthrough_store.reset()
  current, recent, scopes, listeners = {}, {}, {}, {}
end

return walkthrough_store

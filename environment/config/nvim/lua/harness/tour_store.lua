local tour_store = {}

tour_store.EVENT = { start = 'start', stop = 'stop', update = 'update' }

tour_store.RECENT = 20

local current, recent, listeners, scope = nil, {}, {}, nil

local function emit(kind, tour, opts)
  for _, listener in ipairs(vim.list_slice(listeners)) do
    listener(kind, tour, opts)
  end
end

function tour_store.start(tour, opts)
  current = tour

  table.insert(recent, 1, tour)
  recent[tour_store.RECENT + 1] = nil

  emit(tour_store.EVENT.start, tour, opts or {})

  return tour
end

function tour_store.stop()
  local stopped = current

  current, scope = nil, nil

  if stopped then emit(tour_store.EVENT.stop, stopped, {}) end

  return stopped
end

function tour_store.update(update)
  if not current then return false, 'no tour is running; start one with tour_start' end

  emit(tour_store.EVENT.update, current, update)

  return true
end

function tour_store.set_scope(value)
  scope = value
end

function tour_store.scope()
  return scope
end

function tour_store.current()
  return current
end

function tour_store.recent()
  return vim.list_slice(recent)
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
  current, recent, listeners, scope = nil, {}, {}, nil
end

return tour_store

local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local date = lazy('core.utils.date')
local theme = lazy('harness.transcript.theme')
local EVENT = require('harness.types.events').KIND
local SessionsView = lazy('harness.ui.SessionsView')

local sessions = {}

local NEW = { label = '+ New session', description = 'start a fresh conversation', action = 'new' }

function sessions.when(updated_at, now)
  local at = date.from_iso(updated_at)

  return at and date.age(at, now).display or updated_at
end

function sessions.last_prompt(live)
  for i = #live.history, 1, -1 do
    local event = live.history[i]

    if event.kind == EVENT.prompt and not event.steered then
      return (vim.split(event.text, '\n', { plain = true })[1] or ''):sub(1, 60)
    end
  end
end

local function status_of(live, updated_at)
  if not live then return sessions.when(updated_at) end

  local state = #live:waiting() > 0 and 'waiting for you' or live:running() and 'running' or 'idle'
  local prompt = sessions.last_prompt(live)

  return prompt and (state .. ' · ' .. prompt) or state
end

function sessions.rows(listed)
  local rows = { vim.deepcopy(NEW) }

  for _, item in ipairs(listed) do
    local live = item.session
    local mark = '  '

    if live and #live:waiting() > 0 then
      mark = theme.WAITING_ICON[1]
    elseif live and live:running() then
      mark = theme.spinner(Timer.now())[1]
    elseif live then
      mark = theme.IDLE_ICON[1]
    end

    local status = status_of(live, item.updated_at)

    rows[#rows + 1] = {
      label = mark .. (item.title or (live and live.title) or 'untitled'),
      description = status,
      id = item.id,
      title = item.title,
      updated_at = item.updated_at,
      key = live and live.key,
    }
  end

  return rows
end

function sessions.open(opts)
  return SessionsView(opts, sessions.rows, status_of):open()
end

return sessions

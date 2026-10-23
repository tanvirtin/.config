local lazy = require('core.lazy')

local date = lazy('core.utils.date')
local theme = lazy('harness.transcript.theme')
local SessionsView = lazy('harness.ui.SessionsView')

local sessions = {}

local NEW = { label = '+ New session', description = 'start a fresh conversation', action = 'new' }

function sessions.when(updated_at, now)
  local at = date.from_iso(updated_at)

  return at and date.age(at, now).display or updated_at
end

local function status_of(live, updated_at)
  if live then return live:running() and 'running' or 'idle' end

  return sessions.when(updated_at)
end

function sessions.rows(listed)
  local rows = { vim.deepcopy(NEW) }

  for _, item in ipairs(listed) do
    local live = item.session
    local mark = live and (live:running() and theme.RUNNING_ICON or theme.IDLE_ICON) or '  '
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

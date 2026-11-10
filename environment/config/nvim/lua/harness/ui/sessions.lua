local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local agent = lazy('harness.agent')
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

function sessions.rows(listed, current)
  current = current or agent.get().name

  local rows =
    { vim.tbl_extend('force', NEW, { agent = current, description = 'start a fresh conversation with ' .. current }) }

  for _, item in ipairs(listed) do
    local live = item.session
    local mark = '  '

    if live and #live:waiting() > 0 then
      mark = theme.WAITING_ICON[1]
    elseif live and live:running() then
      mark = theme.working_text(Timer.now())
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

  for _, name in ipairs(agent.names()) do
    if name ~= current then
      rows[#rows + 1] = {
        label = '+ New ' .. name .. ' session',
        description = 'start a fresh conversation with ' .. name,
        action = 'new',
        agent = name,
      }
      rows[#rows + 1] = {
        label = '  ' .. name .. ' sessions…',
        description = 'resume an earlier ' .. name .. ' conversation',
        action = 'browse',
        agent = name,
      }
    end
  end

  return rows
end

function sessions.open(opts)
  opts = opts or {}

  local view = SessionsView(opts, function(listed)
    return sessions.rows(listed, opts.agent)
  end, status_of)

  opts.on_browse = opts.on_browse
    or function(name)
      sessions.open(vim.tbl_extend('force', opts, { agent = name }))
    end

  return view:open()
end

return sessions

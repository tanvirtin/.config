local lazy = require('core.lazy')
local compact = require('compact')

local hub = lazy('harness.hub')
local theme = lazy('harness.transcript.theme')

local status = {}

function status.list()
  local ok, sessions = pcall(hub.sessions)

  return ok and (sessions or {}) or {}
end

-- The sessions holding a request the reader has to answer: a tool asking for
-- permission, or a question at the end of a turn.
function status.waiting(list)
  local waiting = {}

  for _, session in ipairs(list or status.list()) do
    if #(session:waiting() or {}) > 0 then waiting[#waiting + 1] = session end
  end

  return waiting
end

local function active(session)
  if session:running() then return true end
  if #session:waiting() > 0 then return true end

  local agents = session.subagents and session.subagents:summary().active or 0

  return agents > 0
end

function status.summary(list)
  local running, agents, waiting = 0, 0, 0

  for _, session in ipairs(list or {}) do
    if session:running() then running = running + 1 end

    local summary = session.subagents and session.subagents:summary() or { active = 0 }

    agents = agents + (summary.active or 0)
    waiting = waiting + #(session:waiting() or {})
  end

  return { running = running, agents = agents, waiting = waiting }
end

function status.text(list)
  local sessions = list or status.list()
  local counts = status.summary(sessions)
  local parts = {}

  if counts.running > 0 then parts[#parts + 1] = theme.RUNNING_ICON .. counts.running .. ' running' end
  if counts.agents > 0 then parts[#parts + 1] = theme.plural(counts.agents, 'agent') end

  local waiting = status.waiting(sessions)

  if #waiting > 0 then
    local icon = type(theme.WAITING_ICON) == 'table' and theme.WAITING_ICON[1] or theme.WAITING_ICON

    if #waiting == 1 then
      parts[#parts + 1] = icon .. 'waiting in ' .. compact.line(waiting[1].title or waiting[1].key or 'a session', 32)
    else
      parts[#parts + 1] = icon .. counts.waiting .. ' waiting'
    end
  end

  return table.concat(parts, ' · ')
end

function status.visible(list)
  local counts = status.summary(list or status.list())

  return counts.running + counts.agents + counts.waiting > 0
end

function status.jump()
  local active_sessions = {}

  for _, session in ipairs(status.list()) do
    if active(session) then active_sessions[#active_sessions + 1] = session end
  end

  if #active_sessions == 1 then return require('harness.ui.display').open(active_sessions[1]) end

  return require('harness.ui.sessions').open()
end

-- Opens the session waiting for an answer and lands on the request itself, so
-- the reader can answer it without hunting through the transcript.
function status.to_waiting()
  local waiting = status.waiting()

  if #waiting == 0 then return require('core.console').notify_now('Harness: no session is waiting for you', 'info') end

  if #waiting > 1 then return require('harness.ui.sessions').open() end

  local session = waiting[1]
  local display = require('harness.ui.display')
  local view = display.view(display.open(session))

  if not view then return end

  local window = require('core.Window').get_current()

  if window:get_buffer().bufnr == view.bufnr then
    window:set_cursor({ 1, 0 })
    require('harness.ui.motions').jump(view, require('harness.ui.motions').KIND.waiting, 1)
  end

  return view
end

return status

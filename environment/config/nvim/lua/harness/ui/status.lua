local lazy = require('core.lazy')

local hub = lazy('harness.hub')
local theme = lazy('harness.transcript.theme')

local status = {}

function status.list()
  local ok, sessions = pcall(hub.sessions)

  return ok and (sessions or {}) or {}
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
  local counts = status.summary(list or status.list())
  local parts = {}

  if counts.running > 0 then parts[#parts + 1] = theme.RUNNING_ICON .. counts.running .. ' running' end
  if counts.agents > 0 then parts[#parts + 1] = theme.plural(counts.agents, 'agent') end

  if counts.waiting > 0 then
    local icon = type(theme.WAITING_ICON) == 'table' and theme.WAITING_ICON[1] or theme.WAITING_ICON

    parts[#parts + 1] = icon .. 'waiting'
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

return status

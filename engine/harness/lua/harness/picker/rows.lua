local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local client = lazy('harness.client')
local glyph = lazy('ui.design.glyph')
local theme = lazy('harness.transcript.theme')
local format = require('harness.picker.format')
local session_types = lazy('harness.types.session')
local session_search = lazy('harness.picker.search')

local ago, home, one_line, state_of = format.ago, format.home, format.one_line, format.state_of
local CORPUS_KINDS, STATE_INDICATOR, STATE_ROLE = format.CORPUS_KINDS, format.STATE_INDICATOR, format.STATE_ROLE

local rows = {}

function rows:_live_sessions()
  local out = {}

  for _, session in ipairs(client.sessions()) do
    if session.state ~= 'closed' then out[#out + 1] = session end
  end

  table.sort(out, function(a, b)
    local aw, bw = #a:waiting() > 0, #b:waiting() > 0

    if aw ~= bw then return aw end
    if a:running() ~= b:running() then return a:running() end

    return (a.times[#a.times] or 0) > (b.times[#b.times] or 0)
  end)

  return out
end

function rows:_live_facts(session, status, agent_name)
  local parts = { agent_name }
  local now = Timer.now()

  if status == 'running' then
    local started = lazy('harness.transcript.view.TranscriptView').turn_started(session)
    local elapsed = started and theme.duration(now - started)

    parts[#parts + 1] = elapsed and ('working ' .. elapsed) or 'working'
  elseif status == 'waiting' then
    parts[#parts + 1] = 'asks you'
  else
    local seen = session.times[#session.times]

    if seen then parts[#parts + 1] = ago(now - seen) end
  end

  if session.dir ~= self._dir then parts[#parts + 1] = home(session.dir) end

  return glyph.join(parts)
end

function rows:_live_row(session)
  local status, status_hl = state_of(session)
  local agent_name = session.agent and session.agent.name or '?'
  local dir = home(session.dir)
  local icon, icon_hl

  if status == 'waiting' then
    icon, icon_hl = glyph.STATUS.attention, status_hl
  elseif status == 'running' then
    icon, icon_hl = glyph.STATUS.running, status_hl
  else
    icon, icon_hl = glyph.STATUS.pending, 'UiMuted'
  end

  return {
    session = session,
    section = 'live',
    icon = icon,
    icon_hl = icon_hl,
    indicator = { STATE_INDICATOR[status], STATE_ROLE[status] },
    label = session_types.label(session),
    description = table.concat({ agent_name, status, dir }, ' '),
    meta = self:_live_facts(session, status, agent_name),
  }
end

function rows:_session_rows()
  local rows = {}

  if self._query == '' then
    rows[#rows + 1] = {
      action = 'new',
      icon = glyph.ACTION.add,
      icon_hl = 'UiAccent',
      label = 'New session',
      description = 'start one on any agent',
      meta = '',
      label_hl = 'UiAccent',
    }
  end

  for _, session in ipairs(self._live) do
    rows[#rows + 1] = self:_live_row(session)
  end

  local open = {}

  for _, session in ipairs(client.sessions()) do
    if session.state ~= 'closed' then open[session.id] = true end
  end

  local stored = {}

  for _, entry in ipairs(self._stored) do
    if not open[entry.id] then stored[#stored + 1] = entry end
  end

  table.sort(stored, function(a, b)
    return (a.updated_at or '') > (b.updated_at or '')
  end)

  for _, entry in ipairs(stored) do
    local title = entry.title or 'untitled'
    local when = entry.updated_at and require('core.utils.date').from_iso(entry.updated_at)
    local age = when and require('core.utils.date').age(when, os.time()).display or ''

    rows[#rows + 1] = {
      stored = entry,
      section = 'recent',
      icon = ' ',
      label = title,
      age = age,
      description = entry.agent .. ' ' .. title,
      meta = glyph.join({ entry.agent, age }),
    }
  end

  return rows
end

function rows:_agent_rows()
  local default = client.agent().name
  local names = client.agents()

  table.sort(names, function(a, b)
    if a == default or b == default then return a == default end

    return a < b
  end)

  local rows = {}

  if self._query == '' then
    rows[#rows + 1] = {
      action = 'back',
      icon = glyph.ACTION.back,
      icon_hl = 'UiMuted',
      label = 'Back to sessions',
      description = 'switch, do not start',
      meta = '',
      label_hl = 'UiMuted',
    }
  end

  for _, name in ipairs(names) do
    local spec = client.agent(name)

    rows[#rows + 1] = {
      action = 'agent',
      agent = name,
      spec = spec,
      icon = glyph.ACTION.add,
      icon_hl = 'UiAccent',
      label = name .. (name == default and ' (default)' or ''),
      description = table.concat({ spec.description or '', spec.command or '' }, ' '),
      meta = spec.model or spec.command or '',
      label_hl = name == default and 'UiAccent' or nil,
    }
  end

  return rows
end

function rows:_body_of(row)
  local session = row.session

  if not session then return nil end

  local cached = self._corpus[session.key]
  local size = #session.history

  if cached and cached.size == size then return cached.text end

  local parts = {}

  for _, event in ipairs(session.history) do
    if CORPUS_KINDS[event.kind] and event.text and event.text ~= '' then parts[#parts + 1] = one_line(event.text) end
  end

  local joined = table.concat(parts, ' ')

  self._corpus[session.key] = { size = size, text = joined }

  return joined
end

function rows:_filter_rows()
  local query = self._query:lower()

  return session_search.rank(self._rows, query, function(row)
    return self:_body_of(row)
  end)
end

return rows

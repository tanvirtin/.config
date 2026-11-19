local lazy = require('core.lazy')

local client = lazy('harness.client')
local glyph = lazy('ui.design.glyph')
local catalog = lazy('ui.pixel.catalog')
local Buffer = lazy('core.editor.Buffer')
local display = lazy('harness.ui.display')
local theme = lazy('harness.transcript.theme')
local format = require('harness.picker.format')
local session_types = lazy('harness.types.session')
local winbar = lazy('harness.transcript.view.winbar')

local home, state_of, turns_of, usage_of = format.home, format.state_of, format.turns_of, format.usage_of
local STATE_ROLE = format.STATE_ROLE

local detail = {}

function detail:_detail_of(row)
  local lines, highlights = {}, {}
  local extras = {}

  local function put(value, hl)
    lines[#lines + 1] = value

    if hl then highlights[#highlights + 1] = { hl = hl, row = #lines - 1, col_range = { from = 0, to = #value } } end
  end

  local function field(key, value, hl)
    if value == nil or value == '' then return end

    value = tostring(value)

    local line = ' ' .. key
    local from = #line + 2

    lines[#lines + 1] = line .. '  ' .. value
    highlights[#highlights + 1] = { hl = 'UiMuted', row = #lines - 1, col_range = { from = 1, to = 1 + #key } }

    if hl then
      highlights[#highlights + 1] = { hl = hl, row = #lines - 1, col_range = { from = from, to = #lines[#lines] } }
    end
  end

  if row and row.session then
    local session = row.session
    local buffer = display.buffer_of(session)
    local status = state_of(session)
    local mode = session:mode()
    local model = mode and (mode.name or mode.id) or 'default'
    local usage = usage_of(session)
    local turns = turns_of(session)

    put(' ' .. session_types.label(session), 'UiTitle')
    field('agent', glyph.join({ session.agent and session.agent.name or '?', model }))
    field('dir', home(session.dir))

    local facts = {}

    if usage and usage.used and usage.size and usage.size > 0 then
      local share = usage.used / usage.size
      local percent = math.floor(share * 100 + 0.5)

      facts[#facts + 1] = percent .. '%'
      extras.ring = {
        row = #lines,
        group = percent >= winbar.CONTEXT_FULL and 'UiError'
          or percent >= winbar.CONTEXT_WARN and 'UiWarn'
          or 'UiAccent',
        share = share,
      }
    end

    if turns > 0 then facts[#facts + 1] = turns .. (turns == 1 and ' turn' or ' turns') end
    if usage and usage.cost then facts[#facts + 1] = string.format('$%.2f', usage.cost) end

    field('context', glyph.join(facts))

    if not extras.ring or #facts == 0 then extras.ring = nil end

    if buffer then
      local buf = Buffer(buffer)

      field(
        'buffer',
        string.format('#%d' .. glyph.SEPARATOR .. '%d lines', buffer, buf:is_valid() and buf:get_line_count() or 0),
        'UiMuted'
      )
    else
      field('buffer', 'not loaded', 'UiMuted')
    end

    if #session.queue > 0 then field('queue', #session.queue .. ' queued', 'UiWarn') end

    extras.badge = status
  elseif row and row.stored then
    local entry = row.stored
    local spec = client.agent(entry.agent)

    put(' ' .. (entry.title or 'untitled'), 'UiTitle')
    field('agent', entry.agent)
    field('used', row.age, 'UiMuted')
    field('dir', home(self._dir))
    field('fork', spec and spec.fork_at_message and 'from any message' or 'not supported', 'UiMuted')

    if self._pending_delete == entry.id then
      put(' press ' .. self:_delete_key() .. ' again to delete for good', 'UiWarn')
    end
  elseif row and row.action == 'agent' then
    put(' ' .. row.agent, 'UiTitle')
    put(' ' .. (row.spec.description or ''), 'UiMuted')
    field('command', row.spec.command)
    field('model', row.spec.model or 'whatever it is set to')
    field('login', row.spec.login, 'UiMuted')
    field('fork', row.spec.fork_at_message and 'from any message' or 'not supported', 'UiMuted')
  elseif row and row.action == 'new' then
    put(' New session', 'UiTitle')
    put(' Start a conversation on any of the agents you have.', 'UiMuted')
    put(' Press <CR> to see them, then <CR> again to start.', 'UiMuted')
  elseif row and row.action == 'back' then
    put(' Sessions', 'UiTitle')
    put(' Switch between the sessions you have open.', 'UiMuted')
    put(' Each one is a transcript buffer; pick it to switch to it.', 'UiMuted')
  else
    put(' Nothing selected', 'UiMuted')
  end

  return lines, highlights, extras
end

function detail:_draw_detail()
  local body = self._body

  if not body or not body.elements.detail or self._loading then return end

  local detail = body.elements.detail

  if not detail:is_valid() then return end

  local row = self._filtered[self._selected]
  local lines, highlights, extras = self:_detail_of(row)
  local marks = {}

  for _, mark in ipairs(highlights) do
    marks[#marks + 1] = mark.hl .. mark.row .. ':' .. mark.col_range.from .. '-' .. mark.col_range.to
  end

  local ring = extras.ring and (extras.ring.group .. math.floor(extras.ring.share * 100 + 0.5)) or ''
  local key = table.concat(lines, '\n') .. '\0' .. table.concat(marks, ';') .. '\0' .. (extras.badge or '') .. ring

  if key == self._detail_drawn and (not extras.badge or self._badge) then return end

  self._detail_drawn = key
  self:_release_badge()

  detail:set_lines(lines)
  detail:clear_extmark_highlights()
  detail:clear_extmark_texts()

  for _, mark in ipairs(highlights) do
    detail:place_extmark_highlight(mark)
  end

  if extras.badge then
    self._badge = catalog.render('badge', { text = extras.badge, color = STATE_ROLE[extras.badge] })
    detail:place_extmark_text({ texts = self._badge.lines[1], row = 0, col = 0, pos = 'eol' })
  end

  if extras.ring then
    local chunk = theme.context_ring(extras.ring.share, extras.ring.group)

    if chunk then
      detail:place_extmark_text({ texts = { { ' ', 'Normal' }, chunk }, row = extras.ring.row, col = 0, pos = 'eol' })
    end
  end
end

return detail

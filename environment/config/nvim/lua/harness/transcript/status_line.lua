local hl = require('ui.hl')
local text = require('core.text')
local compact = require('compact')
local motion = require('ui.motion')
local ASK = require('harness.types.events').ASK
local theme = require('harness.transcript.theme')
local keymaps = require('harness.settings.keymaps')
local settings = require('harness.settings.transcript')
local plan_summary = require('harness.transcript.plan_summary')

local status_line = {}

status_line.RAIL = '▎'

local function queue_lines(state)
  local lines = {}

  for _, text in ipairs(state.queue or {}) do
    local first = vim.split(vim.trim(text), '\n', { plain = true })[1] or ''

    lines[#lines + 1] = {
      { '  ' .. theme.QUEUE_ICON[1], 'UiMuted' },
      { 'queued ', 'UiMuted' },
      { compact.line(first, settings:get('queue_preview')), 'UiPromptBar' },
    }
  end

  return lines
end

local function more(state)
  if #state.asks > 1 then return { string.format('  (+%d more)', #state.asks - 1), 'UiMuted' } end
end

local function fit(state, text, used)
  local width = state.width or settings:get('request_preview')

  return compact.line(text, math.max(width - used, 10))
end

local function ask_lines(state, ask)
  local keys = keymaps:get('transcript')
  local lines = {
    {
      theme.WAITING_ICON,
      { 'Allow ', 'UiWarn' },
      { fit(state, ask.text, 12), 'UiPromptBar' },
      { '?', 'UiWarn' },
      more(state),
    },
  }

  for _, choice in ipairs(ask.choices or state.choices or {}) do
    lines[#lines + 1] = { { '   ' }, { choice.key, 'UiAccent' }, { ' ' .. fit(state, choice.label, 6) } }
  end

  lines[#lines + 1] = { { '   ' }, { keys.interrupt, 'UiAccent' }, { ' interrupt', 'UiMuted' } }

  return lines
end

local function elicitation_lines(state, ask)
  local view = ask:view()
  local keys = keymaps:get('transcript')
  local question = { theme.WAITING_ICON, { fit(state, view.message, 12), 'UiPromptBar' } }

  if view.count > 1 then
    question[#question + 1] = { string.format('  %d/%d', view.step, view.count), 'UiMuted' }
    question[#question + 1] = { ' ' .. plan_summary.bar(view.step, view.count, 6), 'UiAccent' }
  end
  question[#question + 1] = more(state)

  local lines = { question }

  if view.label and (view.count > 1 or view.label ~= view.message) then
    lines[#lines + 1] = { { '   ' }, { fit(state, view.label, 3), 'UiWarn' } }
  end

  if view.url then lines[#lines + 1] = { { '   ' }, { fit(state, view.url, 3), 'UiPath' } } end

  if view.writing then
    lines[#lines + 1] = {
      { '   ' },
      { 'write ', 'UiMuted' },
      { fit(state, view.writing, 46), 'UiPromptBar' },
      { ' in the composer, or close it to go back', 'UiMuted' },
    }
  end

  for _, choice in ipairs(view.choices) do
    local line = { { '   ' }, { choice.key, 'UiAccent' }, { ' ' } }

    if choice.checked ~= nil then line[#line + 1] = { choice.checked and '◉ ' or '○ ', 'UiAccent' } end
    line[#line + 1] = { fit(state, choice.label, 10) }
    if choice.description then
      line[#line + 1] = { '  ' .. fit(state, choice.description, 12 + #choice.label), 'UiMuted' }
    end

    lines[#lines + 1] = line
  end

  if view.error then lines[#lines + 1] = { { '   ' }, { view.error, 'UiWarn' } } end

  lines[#lines + 1] = {
    { '   ' },
    { keys.decline, 'UiAccent' },
    { ' decline   ', 'UiMuted' },
    { keys.interrupt, 'UiAccent' },
    { ' interrupt', 'UiMuted' },
  }

  return lines
end

local function working_line(state, now)
  local request = (state.waiting or {})[1]

  if request then
    return {
      theme.WAITING_ICON,
      { 'waiting for you: ', 'UiWarn' },
      { compact.line(request.title or request.tool or 'a tool', settings:get('request_preview')), 'UiPromptBar' },
      { ' · answer the prompt, or ', 'UiMuted' },
      { keymaps:get('transcript').interrupt, 'UiAccent' },
      { ' to interrupt', 'UiMuted' },
    }
  end

  local elapsed = state.started and now and theme.duration(now - state.started)
  local word, word_hl = theme.working_word(now, state.started)
  local label = state.label or word or 'working'
  local label_hl = state.label and theme.pulse(now) or theme.word_fade(word_hl, now, state.started) or theme.pulse(now)

  return {
    { theme.RUNNING_ICON[1], theme.pulse(now) },
    { label, label_hl },
    { elapsed and ' · ' .. elapsed or '', 'UiMuted' },
    { ' · ', 'UiMuted' },
    { keymaps:get('transcript').interrupt, 'UiAccent' },
    { ' interrupt', 'UiMuted' },
  }
end

local function loading_line(state, now)
  return {
    { theme.motion('loading', now) .. ' ', 'UiAccent' },
    { 'loading', 'UiAccent' },
    { ' · the agent is replaying this session', 'UiMuted' },
  }
end

local function subagents_line(state, now)
  local count = 0

  for _ in pairs(state.active) do
    count = count + 1
  end

  return {
    { theme.RUNNING_ICON[1], theme.pulse(now) },
    { theme.plural(count, 'subagent') .. ' still working', theme.pulse(now) },
  }
end

local function shaded(group)
  if type(group) == 'table' then return vim.list_extend(vim.list_slice(group), { 'UiSurfaceWarn' }) end

  if group == 'UiAccent' then return { group, 'UiSurfaceRaised' } end

  return { group or 'UiMuted', 'UiSurfaceWarn' }
end

local function card(state, lines, now)
  local out = {}

  for index = 1, #lines do
    local line, card_line = lines[index], {}
    local indent = line[1] and line[1][1] == '   '

    local rail = now and theme.pulse(now, 'Warn') or 'UiRailWarn'

    card_line[1] = { indent and status_line.RAIL .. '  ' or status_line.RAIL, { rail, 'UiSurfaceWarn' } }

    for chunk_index = indent and 2 or 1, #line do
      local chunk = line[chunk_index]

      if chunk then card_line[#card_line + 1] = { chunk[1], shaded(chunk[2]) } end
    end

    local used = 0

    for _, chunk in ipairs(card_line) do
      used = used + text.width(chunk[1])
    end

    if state.width and used < state.width then
      card_line[#card_line + 1] = { string.rep(' ', state.width - used), 'UiSurfaceWarn' }
    end

    out[#out + 1] = card_line
  end

  return out
end

local function ask_body(state, ask, now)
  if ask.kind == ASK.elicitation then return card(state, elicitation_lines(state, ask), now) end

  return card(state, ask_lines(state, ask), now)
end

local function compose(state, now)
  local queued = queue_lines(state)
  local ask = (state.asks or {})[1]

  if ask and not state.running then
    local lines = { { { '' } } }

    vim.list_extend(lines, ask_body(state, ask, now))

    return vim.list_extend(lines, queued)
  end

  if state.loading and not state.running then
    local lines = { { { '' } }, loading_line(state, now) }

    return vim.list_extend(lines, queued)
  end

  if not state.running and next(state.active or {}) then
    local lines = { { { '' } }, subagents_line(state, now) }

    return vim.list_extend(lines, queued)
  end

  if not state.running then
    if #queued == 0 then return nil end

    if state.held then
      table.insert(queued, 1, {
        theme.WAITING_ICON,
        { 'waiting for a free turn: other sessions are running', 'UiWarn' },
        { ' (max_running)', 'UiMuted' },
      })
    end

    table.insert(queued, 1, { { '' } })

    return queued
  end

  local body = ask and ask_body(state, ask, now) or { working_line(state, now) }
  local lines = { { { '' } } }

  vim.list_extend(lines, body)

  return vim.list_extend(lines, queued)
end

function status_line.card_of(lines)
  local card = {}

  for _, line in ipairs(lines or {}) do
    local first = line[1] and line[1][1]

    if type(first) == 'string' and first:sub(1, #status_line.RAIL) == status_line.RAIL then card[#card + 1] = line end
  end

  return card
end

local function retint(group, flash)
  if group == 'UiSurfaceWarn' then return flash end
  if type(group) ~= 'table' then return group end

  local out = {}

  for _, name in ipairs(group) do
    out[#out + 1] = name == 'UiSurfaceWarn' and flash or name
  end

  return out
end

function status_line.closing_rows(closing, now)
  local ms = settings:get('flash_ms') * 2
  local progress = ms > 0 and (now - closing.started) / ms or 1

  if progress >= 1 then return {} end

  local step, count = hl.FLASH_STEPS, #closing.lines

  if progress < 0.5 then
    step = motion.steps(hl.FLASH_STEPS, motion.ease.out_cubic(progress * 2))
  else
    count = math.ceil(count * (1 - motion.ease.in_out((progress - 0.5) * 2)))
  end

  local flash = 'UiFlash' .. closing.tone .. step
  local rows = {}

  for index = 1, count do
    local row = {}

    for _, chunk in ipairs(closing.lines[index]) do
      row[#row + 1] = { chunk[1], retint(chunk[2], flash) }
    end

    rows[#rows + 1] = row
  end

  return rows
end

function status_line.lines(state, now)
  local lines = compose(state, now)

  if not state.closing or #(state.asks or {}) > 0 then return lines end

  local rows = status_line.closing_rows(state.closing, now or 0)

  if #rows == 0 then return lines end

  lines = lines or { { { '' } } }

  for index, row in ipairs(rows) do
    table.insert(lines, 1 + index, row)
  end

  return lines
end

return status_line

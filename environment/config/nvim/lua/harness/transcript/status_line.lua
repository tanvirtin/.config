local compact = require('compact')
local ASK = require('harness.types.events').ASK
local theme = require('harness.transcript.theme')
local keymaps = require('harness.settings.keymaps')
local settings = require('harness.settings.transcript')

local status_line = {}

local function queue_lines(state)
  local lines = {}

  for _, text in ipairs(state.queue or {}) do
    local first = vim.split(vim.trim(text), '\n', { plain = true })[1] or ''

    lines[#lines + 1] = {
      { '  ' .. theme.QUEUE_ICON, 'UiMuted' },
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

  if view.count > 1 then question[#question + 1] = { string.format('  %d/%d', view.step, view.count), 'UiMuted' } end
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

    if choice.checked ~= nil then line[#line + 1] = { choice.checked and '[x] ' or '[ ] ', 'UiAccent' } end
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
  local label_hl = state.label and theme.pulse(now) or word_hl or theme.pulse(now)

  return {
    { theme.RUNNING_ICON, theme.pulse(now) },
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

local function ask_body(state, ask)
  if ask.kind == ASK.elicitation then return elicitation_lines(state, ask) end

  return ask_lines(state, ask)
end

function status_line.lines(state, now)
  local queued = queue_lines(state)
  local ask = (state.asks or {})[1]

  if ask and not state.running then
    local lines = { { { '' } } }

    vim.list_extend(lines, ask_body(state, ask))

    return vim.list_extend(lines, queued)
  end

  if state.loading and not state.running then
    local lines = { { { '' } }, loading_line(state, now) }

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

  local body = ask and ask_body(state, ask) or { working_line(state, now) }
  local lines = { { { '' } } }

  vim.list_extend(lines, body)

  return vim.list_extend(lines, queued)
end

return status_line

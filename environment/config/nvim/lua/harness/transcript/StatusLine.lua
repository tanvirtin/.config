local compact = require('compact')
local theme = require('harness.transcript.theme')

local StatusLine = {}

StatusLine.QUEUE_PREVIEW = 120
StatusLine.REQUEST_PREVIEW = 80

local function queue_lines(state)
  local lines = {}

  for _, text in ipairs(state.queue or {}) do
    local first = vim.split(vim.trim(text), '\n', { plain = true })[1] or ''

    lines[#lines + 1] = {
      { '  ' .. theme.QUEUE_ICON, 'UiMuted' },
      { 'queued ', 'UiMuted' },
      { compact.line(first, StatusLine.QUEUE_PREVIEW), 'UiPromptBar' },
    }
  end

  return lines
end

local function ask_lines(state, ask)
  local choices = { { '   ' } }

  for _, choice in ipairs(state.choices or {}) do
    choices[#choices + 1] = { choice.key, 'UiAccent' }
    choices[#choices + 1] = { ' ' .. choice.label .. '   ' }
  end

  choices[#choices + 1] = { '<C-c>', 'UiAccent' }
  choices[#choices + 1] = { ' interrupt', 'UiMuted' }

  local question = { theme.WAITING_ICON, { 'Allow ', 'UiWarn' }, { ask.text, 'UiPromptBar' }, { '?', 'UiWarn' } }

  if #state.asks > 1 then question[#question + 1] = { string.format('  (+%d more)', #state.asks - 1), 'UiMuted' } end

  return { question, choices }
end

local function working_line(state, now)
  local request = (state.waiting or {})[1]

  if request then
    return {
      theme.WAITING_ICON,
      { 'Waiting for you: ', 'UiWarn' },
      { compact.line(request.title or request.tool or 'a tool', StatusLine.REQUEST_PREVIEW), 'UiPromptBar' },
      { ' · answer the prompt, or ', 'UiMuted' },
      { '<C-c>', 'UiAccent' },
      { ' to interrupt', 'UiMuted' },
    }
  end

  local elapsed = state.started and now and theme.duration(now - state.started)

  return {
    { theme.spinner(state.frame) .. ' ', 'UiAccent' },
    { state.label or 'Working', 'UiAccent' },
    { elapsed and ' · ' .. elapsed or '', 'UiMuted' },
    { ' · ', 'UiMuted' },
    { '<C-c>', 'UiAccent' },
    { ' interrupt', 'UiMuted' },
  }
end

function StatusLine.lines(state, now)
  local queued = queue_lines(state)

  if not state.running then
    if #queued == 0 then return nil end

    table.insert(queued, 1, { { '' } })

    return queued
  end

  local ask = (state.asks or {})[1]
  local body = ask and ask_lines(state, ask) or { working_line(state, now) }
  local lines = { { { '' } } }

  vim.list_extend(lines, body)

  return vim.list_extend(lines, queued)
end

return StatusLine

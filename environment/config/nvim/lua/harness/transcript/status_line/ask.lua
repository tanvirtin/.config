local compact = require('compact')
local ASK = require('harness.types.events').ASK
local theme = require('harness.transcript.theme')
local keymaps = require('harness.settings.keymaps')
local settings = require('harness.settings.transcript')
local card = require('harness.transcript.status_line.card')
local plan_summary = require('harness.transcript.plan_summary')

local ask = { id = 'ask', order = 20, exclusive = true }

local function more(state)
  if #state.asks > 1 then return { string.format('  (+%d more)', #state.asks - 1), 'UiMuted' } end
end

local function fit(state, text, used)
  local width = state.width or settings:get('request_preview')

  return compact.line(text, math.max(width - used, 10))
end

local function permission_rows(state, request)
  local keys = keymaps:get('transcript')
  local rows = {
    {
      theme.WAITING_ICON,
      { 'Allow ', 'UiWarn' },
      { fit(state, request.text, 12), 'UiPromptBar' },
      { '?', 'UiWarn' },
      more(state),
    },
  }

  for _, choice in ipairs(request.choices or state.choices or {}) do
    rows[#rows + 1] = { { '   ' }, { choice.key, 'UiAccent' }, { ' ' .. fit(state, choice.label, 6) } }
  end

  rows[#rows + 1] = { { '   ' }, { keys.interrupt, 'UiAccent' }, { ' interrupt', 'UiMuted' } }

  return rows
end

local function elicitation_rows(state, request)
  local view = request:view()
  local keys = keymaps:get('transcript')
  local question = { theme.WAITING_ICON, { fit(state, view.message, 12), 'UiPromptBar' } }

  if view.count > 1 then
    question[#question + 1] = { string.format('  %d/%d', view.step, view.count), 'UiMuted' }
    question[#question + 1] = { ' ' .. plan_summary.bar(view.step, view.count, 6), 'UiAccent' }
  end
  question[#question + 1] = more(state)

  local rows = { question }

  if view.label and (view.count > 1 or view.label ~= view.message) then
    rows[#rows + 1] = { { '   ' }, { fit(state, view.label, 3), 'UiWarn' } }
  end

  if view.url then rows[#rows + 1] = { { '   ' }, { fit(state, view.url, 3), 'UiPath' } } end

  if view.writing then
    rows[#rows + 1] = {
      { '   ' },
      { 'write ', 'UiMuted' },
      { fit(state, view.writing, 46), 'UiPromptBar' },
      { ' in the composer, or close it to go back', 'UiMuted' },
    }
  end

  for _, choice in ipairs(view.choices) do
    local row = { { '   ' }, { choice.key, 'UiAccent' }, { ' ' } }

    if choice.checked ~= nil then row[#row + 1] = { choice.checked and '◉ ' or '○ ', 'UiAccent' } end
    row[#row + 1] = { fit(state, choice.label, 10) }
    if choice.description then
      row[#row + 1] = { '  ' .. fit(state, choice.description, 12 + #choice.label), 'UiMuted' }
    end

    rows[#rows + 1] = row
  end

  if view.error then rows[#rows + 1] = { { '   ' }, { view.error, 'UiWarn' } } end

  rows[#rows + 1] = {
    { '   ' },
    { keys.decline, 'UiAccent' },
    { ' decline   ', 'UiMuted' },
    { keys.interrupt, 'UiAccent' },
    { ' interrupt', 'UiMuted' },
  }

  return rows
end

function ask.applies(state)
  return #(state.asks or {}) > 0
end

function ask.lines(state, now)
  local request = state.asks[1]

  if request.kind == ASK.elicitation then return card.build(state, elicitation_rows(state, request), now) end

  return card.build(state, permission_rows(state, request), now)
end

return ask

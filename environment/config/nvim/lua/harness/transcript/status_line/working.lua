local compact = require('compact')
local theme = require('harness.transcript.theme')
local keymaps = require('harness.settings.keymaps')
local settings = require('harness.settings.transcript')

local working = { id = 'working', order = 50, exclusive = true }

function working.applies(state)
  return state.running == true
end

function working.lines(state, now)
  local request = (state.waiting or {})[1]

  if request then
    return {
      {
        theme.WAITING_ICON,
        { 'waiting for you: ', 'UiWarn' },
        { compact.line(request.title or request.tool or 'a tool', settings:get('request_preview')), 'UiPromptBar' },
        { ' · answer the prompt, or ', 'UiMuted' },
        { keymaps:get('transcript').interrupt, 'UiAccent' },
        { ' to interrupt', 'UiMuted' },
      },
    }
  end

  local elapsed = state.started and now and theme.duration(now - state.started)
  local word, word_hl = theme.working_word(now, state.started)
  local label = state.label or word or 'working'
  local label_hl = state.label and theme.pulse(now) or theme.glint(word_hl, now, state.started) or theme.pulse(now)

  return {
    vim.list_extend(theme.working(now, state.started), {
      { ' ' .. label, label_hl },
      { elapsed and ' · ' .. elapsed or '', 'UiMuted' },
      { ' · ', 'UiMuted' },
      { keymaps:get('transcript').interrupt, 'UiAccent' },
      { ' interrupt', 'UiMuted' },
    }),
  }
end

return working

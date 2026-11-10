local theme = require('harness.transcript.theme')

local loading = { id = 'loading', order = 30, exclusive = true }

function loading.applies(state)
  return state.loading == true and not state.running
end

function loading.lines(_, now)
  return {
    vim.list_extend(theme.sweep(now), {
      { ' loading', 'UiAccent' },
      { ' · the agent is replaying this session', 'UiMuted' },
    }),
  }
end

return loading

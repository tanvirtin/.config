local theme = require('harness.transcript.theme')

local subagents = { id = 'subagents', order = 40, exclusive = true }

function subagents.applies(state)
  return not state.running and next(state.active or {}) ~= nil
end

function subagents.lines(state, now)
  local count = 0

  for _ in pairs(state.active) do
    count = count + 1
  end

  return {
    vim.list_extend(theme.working(now), {
      { ' ' .. theme.plural(count, 'subagent') .. ' still working', theme.pulse(now) },
    }),
  }
end

return subagents

local compact = require('compact')
local theme = require('harness.transcript.theme')
local settings = require('harness.settings.transcript')

local queue = { id = 'queue', order = 100, exclusive = false }

queue.held = { id = 'held', order = 45, exclusive = true }

function queue.applies(state)
  return #(state.queue or {}) > 0
end

function queue.lines(state)
  local rows = {}

  for _, text in ipairs(state.queue) do
    local first = vim.split(vim.trim(text), '\n', { plain = true })[1] or ''

    rows[#rows + 1] = {
      { '  ' .. theme.QUEUE_ICON[1], 'UiMuted' },
      { 'queued ', 'UiMuted' },
      { compact.line(first, settings:get('queue_preview')), 'UiPromptBar' },
    }
  end

  return rows
end

function queue.held.applies(state)
  return not state.running and state.held and queue.applies(state)
end

function queue.held.lines()
  return {
    {
      theme.WAITING_ICON,
      { 'waiting for a free turn: other sessions are running', 'UiWarn' },
      { ' (max_running)', 'UiMuted' },
    },
  }
end

return queue

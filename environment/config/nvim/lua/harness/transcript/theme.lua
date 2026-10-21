local Block = require('harness.transcript.Block')

local theme = {}

theme.SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

theme.TOOL_ICONS = {
  [Block.STATUS.pending] = { '󰔟 ', 'UiToolPending' },
  [Block.STATUS.in_progress] = { '󰔟 ', 'UiToolPending' },
  [Block.STATUS.completed] = { '󰄬 ', 'UiToolDone' },
  [Block.STATUS.failed] = { '󰅖 ', 'UiToolFailed' },
}

theme.STOP_ICONS = {
  end_turn = { '󰄬 ', 'UiToolDone' },
  cancelled = { '󰜺 ', 'UiWarn' },
}

theme.STOP_FALLBACK_ICON = { '󰀪 ', 'UiWarn' }
theme.WAITING_ICON = { '󰀦 ', 'UiWarn' }
theme.QUEUE_ICON = '󰔟 '
theme.USER_ICON = '󰀄 '
theme.AGENT_ICON = '󰚩 '
theme.PATH_ICON = '󰈔 '
theme.GUTTER = '  │ '
theme.GUTTER_PRIORITY = 10
theme.SYNTAX_PRIORITY = 150
theme.SEPARATOR_WIDTH = 400
theme.HUNK = '┈┈┈┈'

function theme.spinner(frame)
  return theme.SPINNER[((frame or 1) - 1) % #theme.SPINNER + 1]
end

function theme.duration(ms)
  if not ms or ms < 1000 then return nil end

  local seconds = math.floor(ms / 1000)

  if seconds < 60 then return seconds .. 's' end

  return string.format('%dm %ds', math.floor(seconds / 60), seconds % 60)
end

function theme.plural(n, word)
  return string.format('%d %s%s', n, word, n == 1 and '' or 's')
end

return theme

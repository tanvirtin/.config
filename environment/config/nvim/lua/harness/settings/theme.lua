local Config = require('core.Config')

return Config({
  spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
  tool_icons = {
    pending = { '󰔟 ', 'UiToolPending' },
    in_progress = { '󰔟 ', 'UiToolPending' },
    completed = { '󰄬 ', 'UiToolDone' },
    failed = { '󰅖 ', 'UiToolFailed' },
  },
  stop_icons = {
    end_turn = { '󰄬 ', 'UiToolDone' },
    cancelled = { '󰜺 ', 'UiWarn' },
  },
  stop_fallback_icon = { '󰀪 ', 'UiWarn' },
  waiting_icon = { '󰀦 ', 'UiWarn' },
  queue_icon = '󰔟 ',
  user_icon = '󰀄 ',
  agent_icon = '󰚩 ',
  path_icon = '󰈔 ',
  gutter = '  │ ',
  hunk = '┈┈┈┈',
  collapsed_icon = '󰁝 ',
  highlights = {},
})

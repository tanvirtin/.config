local Config = require('core.Config')

return Config({
  spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
  tool_icons = {
    pending = { '○ ', 'UiToolPending' },
    in_progress = { '○ ', 'UiToolPending' },
    completed = { '✓ ', 'UiToolDone' },
    failed = { '✗ ', 'UiToolFailed' },
  },
  waiting_icon = { '◆ ', 'UiWarn' },
  queue_icon = '󰔟 ',
  prompt_icon = '❯',
  path_icon = '󰈔 ',
  verb_width = 8,
  gutter = '│ ',
  branch = '├ ',
  branch_end = '└ ',
  rule = '─',
  hunk = '┈┈┈┈',
  collapsed_icon = '󰁝 ',
  highlights = {},
})

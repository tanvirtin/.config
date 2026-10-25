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
  queue_icon = '· ',
  running_icon = '◆ ',
  idle_icon = '○ ',
  current_icon = '✓ ',
  mode_format = '[%s]',
  plan_icons = {
    completed = { '✓ ', 'UiMuted' },
    in_progress = { '◆ ', 'UiAccent' },
    pending = { '○ ', 'UiMuted' },
  },
  prompt_icon = '❯',
  path_icon = '󰈔 ',
  verb_width = 8,
  gutter = '│ ',
  branch = '├ ',
  branch_end = '└ ',
  rule = '─',
  artifact_border = 'top',
  artifact_rule = '─',
  hunk = '┈┈┈┈',
  collapsed_icon = '⋯ ',
  highlights = {},
})

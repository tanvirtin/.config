local Config = require('core.Config')

return Config({
  motion = {
    reduced = false,
    pulse_ms = 100,
  },
  tool_icons = {
    pending = { '○ ', 'UiToolPending' },
    in_progress = { '⠶ ', 'UiAccent' },
    completed = { '✓ ', 'UiToolDone' },
    failed = { '✗ ', 'UiToolFailed' },
  },
  waiting_icon = { '◆ ', 'UiWarn' },
  queue_icon = { '· ', 'UiMuted' },
  idle_icon = { '○ ', 'UiMuted' },
  current_icon = '✓ ',
  mode_format = '[%s]',
  plan_icons = {
    completed = { '✓ ', 'UiMuted' },
    in_progress = { '◐ ', 'UiAccent' },
    pending = { '○ ', 'UiMuted' },
  },
  prompt_icon = '❯',
  path_icon = '󰈔 ',
  verb_width = 8,
  gutter = '│ ',
  sign = '▎',
  branch = '├ ',
  branch_end = '└ ',
  rule = '─',
  artifact_border = 'top',
  artifact_rule = '┄',
  hunk = '┈┈┈┈',
  collapsed_icon = '⋯ ',
  highlights = {},
})

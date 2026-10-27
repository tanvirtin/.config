local Config = require('core.Config')

return Config({
  motion = {
    pulse_ms = 300,
    working = {
      word_ms = 3000,
      words = { 'working', 'pondering', 'noodling', 'cogitating', 'musing', 'tinkering' },
    },
    thinking = { ms = 300, frames = { 'thinking.', 'thinking..', 'thinking...' } },
    loading = {
      ms = 100,
      frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
    },
  },
  tool_icons = {
    pending = { '○ ', 'UiToolPending' },
    in_progress = { '◆ ', 'UiAccent' },
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

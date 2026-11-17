local Config = require('core.Config')
local glyph = require('ui.design.glyph')

return Config({
  motion = {
    reduced = false,
  },
  tool_icons = {
    pending = { glyph.STATUS.pending .. ' ', 'UiToolPending' },
    in_progress = { glyph.STATUS.running .. ' ', 'UiAccent' },
    completed = { glyph.STATUS.done .. ' ', 'UiToolDone' },
    failed = { glyph.STATUS.failed .. ' ', 'UiToolFailed' },
  },
  waiting_icon = { glyph.STATUS.attention .. ' ', 'UiWarn' },
  queue_icon = { glyph.DOT .. ' ', 'UiMuted' },
  idle_icon = { glyph.STATUS.pending .. ' ', 'UiMuted' },
  current_icon = glyph.STATUS.done .. ' ',
  mode_format = '[%s]',
  plan_icons = {
    completed = { glyph.STATUS.done .. ' ', 'UiMuted' },
    in_progress = { glyph.STATUS.partial .. ' ', 'UiAccent' },
    pending = { glyph.STATUS.pending .. ' ', 'UiMuted' },
  },
  prompt_icon = glyph.PROMPT,
  path_icon = glyph.FILE .. ' ',
  verb_width = 8,
  gutter = glyph.TREE.gutter .. ' ',
  sign = glyph.LINE.rail,
  branch = glyph.TREE.branch .. ' ',
  branch_end = glyph.TREE.branch_end .. ' ',
  rule = glyph.LINE.rule,
  artifact_border = 'top',
  artifact_rule = glyph.LINE.dashed,
  hunk = string.rep(glyph.LINE.dotted, 4),
  collapsed_icon = glyph.STATUS.more .. ' ',
  highlights = {},
})

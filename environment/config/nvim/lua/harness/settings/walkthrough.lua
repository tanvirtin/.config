local Config = require('core.Config')

return Config({
  note = 'inline',
  note_width = 0.42,
  note_min_width = 36,
  note_height = 18,
  note_scroll = 3,
  diff_layout = 'auto',
  split_min_width = 140,
  model = { claude = 'claude-haiku-5-5' },
  reader_lines = 160,
})

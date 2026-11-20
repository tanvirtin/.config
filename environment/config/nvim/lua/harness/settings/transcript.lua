local Config = require('core.Config')
local tokens = require('ui.design.motion')

return Config({
  tick_ms = tokens.STEP_MS,
  animate_ms = tokens.FRAME_MS,
  flash_ms = tokens.DURATION.slow,
  fade_ms = tokens.DURATION.fast,
  fade_rows = 40,
  toast = { in_ms = tokens.DURATION.fast, hold_ms = 2500, out_ms = tokens.DURATION.moderate },
  watch_ms = 150,
  frame_ms = 16,
  margin_screens = 2,
  preview_lines = 3,
  output_max = 200,
  queue_preview = 120,
  request_preview = 80,
  live_turns = 50,
  diff_context = 3,
  diff_preview_lines = 12,
  diff_layout = 'auto',
  diff_overflow = 'truncate',
  argument_max = 120,
  hints = true,
  tile_width = 0.35,
  tile_min_width = 40,
})

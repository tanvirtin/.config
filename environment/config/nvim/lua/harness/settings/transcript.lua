local Config = require('core.Config')

return Config({
  tick_ms = 100,
  frame_ms = 16,
  anchor_prompt = true,
  margin_screens = 2,
  preview_lines = 5,
  output_max = 200,
  queue_preview = 120,
  request_preview = 80,
  live_turns = 50,
  diff_context = 3,
  diff_preview_lines = 12,
  argument_max = 120,
})

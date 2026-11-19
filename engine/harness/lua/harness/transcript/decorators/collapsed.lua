local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')
local keymaps = require('harness.settings.keymaps')

return function(block)
  local out = {}
  local line = block.lines[1]
  local key = keymaps:get('transcript').activate
  local hint = line:find(key, 1, true)

  MarkSpec.add(out, block.start, 0, { virt_text = { { theme.COLLAPSED_ICON, 'UiMuted' } }, virt_text_pos = 'inline' })
  MarkSpec.add(out, block.start, 0, { end_col = #line, hl_group = 'UiMuted' })

  if hint then MarkSpec.add(out, block.start, hint - 1, { end_col = hint - 1 + #key, hl_group = 'UiAccent' }) end

  return out
end

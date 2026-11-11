local MarkSpec = require('ui.MarkSpec')
local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')

local RAILS = { 'UiRailMuted', 'UiRailInfo', 'UiRailAccent', 'UiRailWarn' }

local function rail(out, row, glyph, indented, group)
  if indented then
    MarkSpec.add(out, row, 0, {
      virt_text = { { glyph, group } },
      virt_text_pos = 'overlay',
      virt_text_repeat_linebreak = true,
      priority = theme.GUTTER_PRIORITY,
    })
  else
    MarkSpec.add(out, row, 0, {
      virt_text = { { glyph, group } },
      virt_text_pos = 'inline',
      priority = theme.GUTTER_PRIORITY,
    })
  end
end

return function(block)
  local out = {}

  if not block.depth then return out end

  local group = RAILS[(block.depth - 1) % #RAILS + 1]

  local last = block.start + #block.lines - 1

  local closes = block.last_child and block.kind == Block.KIND.tool and last == block.start

  for row = block.start, last do
    local head = block.kind == Block.KIND.tool and row == block.start

    rail(out, row, closes and theme.BRANCH_END or head and theme.BRANCH or theme.GUTTER, block.indented, group)
  end

  if block.finish > last + 1 and not closes then
    rail(out, last + 1, block.last_child and theme.BRANCH_END or theme.GUTTER, false, group)
  end

  return out
end

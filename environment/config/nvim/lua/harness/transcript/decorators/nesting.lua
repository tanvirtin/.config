local Block = require('harness.transcript.Block')
local MarkSpec = require('ui.MarkSpec')
local theme = require('harness.transcript.theme')

local function rail(out, row, glyph, indented)
  if indented then
    MarkSpec.add(out, row, 0, {
      virt_text = { { glyph, 'UiMuted' } },
      virt_text_pos = 'overlay',
      virt_text_repeat_linebreak = true,
      priority = theme.GUTTER_PRIORITY,
    })
  else
    MarkSpec.add(out, row, 0, {
      virt_text = { { glyph, 'UiMuted' } },
      virt_text_pos = 'inline',
      priority = theme.GUTTER_PRIORITY,
    })
  end
end

return function(block)
  local out = {}

  if not block.depth then return out end

  local last = block.start + #block.lines - 1

  for row = block.start, last do
    local head = block.kind == Block.KIND.tool and row == block.start

    rail(out, row, head and theme.BRANCH or theme.GUTTER, block.indented)
  end

  if block.finish > last + 1 then rail(out, last + 1, block.last_child and theme.BRANCH_END or theme.GUTTER, false) end

  return out
end

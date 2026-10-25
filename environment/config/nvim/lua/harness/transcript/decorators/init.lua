local MarkSpec = require('ui.MarkSpec')
local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')

local decorators = {}

decorators.KIND = {
  [Block.KIND.collapsed] = require('harness.transcript.decorators.collapsed'),
  [Block.KIND.prompt] = require('harness.transcript.decorators.prompt'),
  [Block.KIND.tool] = require('harness.transcript.decorators.tool'),
  [Block.KIND.diff] = require('harness.transcript.decorators.diff'),
  [Block.KIND.thought] = require('harness.transcript.decorators.thought'),
  [Block.KIND.stop] = require('harness.transcript.decorators.stop'),
  [Block.KIND.note] = require('harness.transcript.decorators.note'),
  [Block.KIND.plan] = require('harness.transcript.decorators.plan'),
}

decorators.nesting = require('harness.transcript.decorators.nesting')

decorators.BORDER = { top = { top = true }, both = { top = true, bottom = true } }

local function border(block)
  local line = { { string.rep(theme.ARTIFACT_RULE, theme.RULE_WIDTH), 'UiArtifactBorder' } }

  if block.depth then table.insert(line, 1, { theme.GUTTER, 'UiMuted' }) end

  return { line }
end

function decorators.frame(block, out)
  local edges = decorators.BORDER[theme.ARTIFACT_BORDER]

  if not edges then return out end

  if edges.top and block.frame_top then
    MarkSpec.add(out, block.start, 0, { virt_lines = border(block), virt_lines_above = true })
  end

  if edges.bottom and block.frame_bottom then
    local after = block.start + #block.lines

    if block.finish > after and not block.tight then
      MarkSpec.add(out, after, 0, { virt_lines = border(block), virt_lines_above = true })
    else
      MarkSpec.add(out, math.max(block.start, after - 2), 0, { virt_lines = border(block) })
    end
  end

  return out
end

function decorators.decorate(block, ctx)
  local decorate = decorators.KIND[block.kind]
  local out = decorate and decorate(block, ctx) or {}

  for _, mark in ipairs(decorators.nesting(block, ctx)) do
    out[#out + 1] = mark
  end

  decorators.frame(block, out)

  if block.tight and not block.last_child and block.finish > block.start + #block.lines then
    MarkSpec.add(out, block.finish - 1, 0, { conceal_lines = '' })
  end

  return out
end

return decorators

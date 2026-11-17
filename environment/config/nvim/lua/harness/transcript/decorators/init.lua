local text = require('core.text')
local MarkSpec = require('ui.MarkSpec')
local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')
local BlockBuilder = require('harness.transcript.BlockBuilder')

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

local function border(block, ctx)
  local inset = block.depth and text.width(theme.GUTTER) or 0
  local line = theme.rule(ctx, theme.ARTIFACT_RULE, 'UiArtifactBorder', 'faint', inset)

  if block.depth then table.insert(line, 1, { theme.GUTTER, 'UiMuted' }) end

  return { line }
end

function decorators.frame(block, out, ctx)
  local edges = decorators.BORDER[theme.ARTIFACT_BORDER]

  if not edges then return out end

  if edges.top and block.frame_top then
    MarkSpec.add(out, block.start, 0, { virt_lines = border(block, ctx), virt_lines_above = true })
  end

  if edges.bottom and block.frame_bottom then
    local after = block.start + #block.lines

    if block.finish > after and not block.tight then
      MarkSpec.add(out, after, 0, { virt_lines = border(block, ctx), virt_lines_above = true })
    else
      MarkSpec.add(out, math.max(block.start, after - 2), 0, { virt_lines = border(block, ctx) })
    end
  end

  return out
end

local function subagent_count(block)
  if not (block.open_parent and block.siblings) then return 0 end

  return block.siblings - BlockBuilder.SUBAGENT_TAIL
end

local function concealed(block)
  local out = {}

  for row = block.start, block.finish - 1 do
    MarkSpec.add(out, row, 0, { conceal_lines = '' })
  end

  return out
end

local function earlier(block, out)
  local count = subagent_count(block)

  if count < 1 or block.sibling ~= count + 1 then return end

  MarkSpec.add(out, block.start, 0, {
    virt_lines = {
      { { theme.GUTTER, decorators.nesting.group(block.depth or 1) }, { '+' .. count .. ' earlier', 'UiMuted' } },
    },
    virt_lines_above = true,
  })
end

local function sign_group(block)
  if block.kind == Block.KIND.diff then return 'UiAdded' end
  if block.kind == Block.KIND.tool and block.status == Block.STATUS.failed and not block.interrupted then
    return 'UiToolFailed'
  end
  if block.kind == Block.KIND.note and block.label and not Block.SETTLED_NOTES[block.label] then
    return block.label == 'error' and 'UiError' or 'UiWarn'
  end
end

local function signs(block, out)
  local group = sign_group(block)

  if not group or theme.SIGN == '' then return end

  for row = block.start, block.start + #block.lines - 1 do
    MarkSpec.add(out, row, 0, { sign_text = theme.SIGN, sign_hl_group = group })
  end
end

function decorators.decorate(block, ctx)
  if block.open_parent and block.sibling <= subagent_count(block) then return concealed(block) end

  local decorate = decorators.KIND[block.kind]
  local out = decorate and decorate(block, ctx) or {}

  for _, mark in ipairs(decorators.nesting.marks(block)) do
    out[#out + 1] = mark
  end

  earlier(block, out)
  decorators.frame(block, out, ctx)
  signs(block, out)

  if block.tight and not block.last_child and block.finish > block.start + #block.lines then
    MarkSpec.add(out, block.finish - 1, 0, { conceal_lines = '' })
  end

  return out
end

return decorators

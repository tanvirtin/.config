local Block = require('harness.transcript.Block')

local decorators = {}

decorators.KIND = {
  [Block.KIND.collapsed] = require('harness.transcript.decorators.collapsed'),
  [Block.KIND.prompt] = require('harness.transcript.decorators.prompt'),
  [Block.KIND.tool] = require('harness.transcript.decorators.tool'),
  [Block.KIND.diff] = require('harness.transcript.decorators.diff'),
  [Block.KIND.thought] = require('harness.transcript.decorators.thought'),
  [Block.KIND.stop] = require('harness.transcript.decorators.stop'),
  [Block.KIND.note] = require('harness.transcript.decorators.note'),
}

decorators.nesting = require('harness.transcript.decorators.nesting')

function decorators.decorate(block, ctx)
  local decorate = decorators.KIND[block.kind]
  local out = decorate and decorate(block, ctx) or {}

  for _, mark in ipairs(decorators.nesting(block, ctx)) do
    out[#out + 1] = mark
  end

  return out
end

return decorators

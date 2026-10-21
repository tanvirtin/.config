local BlockBuilder = require('harness.transcript.BlockBuilder')
local EditPatches = require('harness.transcript.EditPatches')
local buffers = require('core.buffers')

local TextRenderer = {}

function TextRenderer.render(history, title, opts)
  opts = opts or {}

  return BlockBuilder.lines(BlockBuilder.build(history, title, {
    outputs = false,
    edits = opts.edits or EditPatches(buffers.lines_of),
  }))
end

return TextRenderer

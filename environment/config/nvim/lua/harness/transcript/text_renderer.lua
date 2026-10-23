local buffers = require('core.buffers')
local EditLog = require('harness.edits.EditLog')
local BlockBuilder = require('harness.transcript.BlockBuilder')

local text_renderer = {}

function text_renderer.render(history, title, opts)
  opts = opts or {}

  return BlockBuilder.lines(BlockBuilder.build(history, title, {
    outputs = false,
    edits = opts.edits or EditLog(buffers.lines_of),
  }))
end

return text_renderer

local client = require('sn.client')
local buffers = require('core.editor.buffers')
local BlockBuilder = require('sn.transcript.model.BlockBuilder')

local text_renderer = {}

function text_renderer.render(history, title, opts)
  opts = opts or {}

  return BlockBuilder.lines(BlockBuilder.build(history, title, {
    outputs = false,
    edits = opts.edits or client.edit_log(buffers.lines_of),
  }))
end

return text_renderer

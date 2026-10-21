local BlockBuilder = require('harness.transcript.BlockBuilder')

local TextRenderer = {}

function TextRenderer.render(history, title)
  return BlockBuilder.lines(BlockBuilder.build(history, title, { outputs = false }))
end

return TextRenderer

local Block = require('harness.transcript.Block')
local theme = require('harness.transcript.theme')

local context = {}

context.FINISHED = { [Block.STATUS.completed] = true, [Block.STATUS.failed] = true }

function context.live_tool(block, ctx)
  return block.kind == Block.KIND.tool and ctx.running == true and not context.FINISHED[block.status]
end

function context.waiting_for(block, ctx)
  for _, request in ipairs(ctx.waiting or {}) do
    if request.id and request.id == block.id then return request end
  end
end

function context.spinner(ctx)
  return theme.spinner(ctx.frame)
end

return context

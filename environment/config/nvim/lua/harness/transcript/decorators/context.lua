local Block = require('harness.transcript.Block')

local context = {}

context.FINISHED = { [Block.STATUS.completed] = true, [Block.STATUS.failed] = true }

function context.live_tool(block, ctx)
  if block.kind ~= Block.KIND.tool then return false end
  if ctx.active and ((block.id and ctx.active[block.id]) or (block.parent and ctx.active[block.parent])) then
    return true
  end

  return ctx.running == true and not context.FINISHED[block.status]
end

function context.waiting_for(block, ctx)
  for _, request in ipairs(ctx.waiting or {}) do
    if request.id and request.id == block.id then return request end
  end
end

return context

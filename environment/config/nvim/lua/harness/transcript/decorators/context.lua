local Block = require('harness.transcript.model.Block')

local context = {}

context.FINISHED = { [Block.STATUS.completed] = true, [Block.STATUS.failed] = true }

function context.live_tool(block, ctx)
  if block.kind == Block.KIND.fleet then return ctx.active ~= nil and ctx.active[block.id] == true end
  if block.kind ~= Block.KIND.tool then return false end
  if ctx.active and block.id and ctx.active[block.id] then return true end
  if block.settled or context.FINISHED[block.status] then return false end

  return ctx.running == true or (ctx.active ~= nil and block.parent ~= nil and ctx.active[block.parent] == true)
end

function context.waiting_for(block, ctx)
  for _, request in ipairs(ctx.waiting or {}) do
    if request.id and request.id == block.id then return request end
  end
end

return context

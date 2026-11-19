local Block = require('sn.transcript.model.Block')
local context = require('sn.transcript.decorators.context')

local eq = assert.are.same

local function tool(status, parent)
  return { kind = Block.KIND.tool, id = 'child', status = status, parent = parent }
end

describe('sn.transcript.decorators.context:', function()
  it('keeps the unfinished tools of a running subagent live', function()
    eq(true, context.live_tool(tool(Block.STATUS.pending, 'agent'), { active = { agent = true } }))
  end)

  it('settles the finished tools of a running subagent', function()
    local ctx = { active = { agent = true } }

    eq(false, context.live_tool(tool(Block.STATUS.completed, 'agent'), ctx))
    eq(false, context.live_tool(tool(Block.STATUS.failed, 'agent'), ctx))
  end)

  it('keeps a running subagent itself live', function()
    local block = { kind = Block.KIND.tool, id = 'agent', status = Block.STATUS.completed }

    eq(true, context.live_tool(block, { active = { agent = true } }))
  end)

  it('keeps unfinished tools live while the turn runs', function()
    eq(true, context.live_tool(tool(Block.STATUS.pending), { running = true }))
    eq(false, context.live_tool(tool(Block.STATUS.pending), { running = false }))
  end)

  it('settles a tool that its finished subagent left behind', function()
    local block = tool(Block.STATUS.pending, 'agent')

    block.settled = true

    eq(false, context.live_tool(block, { running = true, active = {} }))
  end)
end)

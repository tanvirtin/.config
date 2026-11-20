local TurnIndex = require('harness.session.TurnIndex')

local eq = assert.are.same

local function history()
  return {
    { kind = 'prompt', text = 'one' },
    { kind = 'tool_call', id = 'a' },
    { kind = 'tool_update', id = 'a' },
    { kind = 'stop' },
    { kind = 'prompt', text = 'steer', steered = true },
    { kind = 'user', text = 'two' },
    { kind = 'tool_update', id = 'a' },
    { kind = 'tool_update', id = 'b' },
  }
end

describe('harness.session.TurnIndex:', function()
  it('finds where each turn starts, leaving out steered prompts', function()
    eq({ 1, 6 }, TurnIndex():rebuild(history()).starts)
  end)

  it('lists the updates of each tool in order', function()
    local index = TurnIndex():rebuild(history())

    eq({ 3, 7 }, index.updates.a)
    eq({ 8 }, index.updates.b)
  end)

  it('names the turn of every update that lands after the turn that called its tool', function()
    eq({ 1 }, TurnIndex():rebuild(history()).late)
  end)

  it('grows one event at a time to the same index a full scan gives', function()
    local list, grown = history(), TurnIndex()

    for i = 1, #list do
      grown:add(list, i)
    end

    local scanned = TurnIndex():rebuild(list)

    eq(scanned.starts, grown.starts)
    eq(scanned.updates, grown.updates)
    eq(scanned.late, grown.late)
    eq(true, grown:fresh(list))
  end)

  it('is stale once the history has a different length, and of() scans again', function()
    local list = history()
    local index = TurnIndex():rebuild(list)

    list[#list + 1] = { kind = 'prompt', text = 'three' }

    eq(false, index:fresh(list))
    eq({ 1, 6, 9 }, TurnIndex.of(list, index).starts)
    eq(index, TurnIndex.of(list[1] and history(), index))
  end)
end)

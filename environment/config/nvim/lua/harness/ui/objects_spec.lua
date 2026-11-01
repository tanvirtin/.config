local objects = require('harness.ui.objects')
local Block = require('harness.transcript.Block')

local eq = assert.are.same

local function block(kind, start, last)
  local lines = {}

  for i = start, last do
    lines[#lines + 1] = 'x'
  end

  local made = Block.make(kind, lines)

  made.start, made.finish = start, last + 2

  return made
end

describe('harness.ui.objects:', function()
  local blocks = {
    block(Block.KIND.prompt, 0, 1),
    block(Block.KIND.message, 3, 5),
    block(Block.KIND.tool, 7, 9),
    block(Block.KIND.prompt, 11, 11),
    block(Block.KIND.message, 13, 14),
  }

  local function range(row, kind, around)
    return { objects.range(blocks, row, kind, around) }
  end

  it('takes a whole turn, prompt included, with a', function()
    eq({ 0, 9 }, range(4, 'turn', true))
    eq({ 0, 9 }, range(0, 'turn', true))
    eq({ 11, 14 }, range(14, 'turn', true))
  end)

  it('takes only the replies of a turn with i', function()
    eq({ 2, 9 }, range(8, 'turn', false))
  end)

  it('takes the message or tool under the cursor', function()
    eq({ 3, 5 }, range(4, 'message', true))
    eq({ 4, 5 }, range(4, 'message', false))
    eq({ 7, 9 }, range(8, 'tool', true))
    eq({ 8, 9 }, range(8, 'tool', false))
  end)

  it('finds nothing when the cursor is on another kind', function()
    eq({}, range(8, 'message', true))
    eq({}, range(4, 'tool', true))
    eq({}, range(2, 'tool', true))
  end)
end)

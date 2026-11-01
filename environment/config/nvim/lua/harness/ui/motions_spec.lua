local motions = require('harness.ui.motions')
local Block = require('harness.transcript.Block')

local eq = assert.are.same

local function block(kind, start, fields)
  local made = Block.make(kind, { 'x' }, fields)

  made.start = start

  return made
end

describe('harness.ui.motions:', function()
  local blocks = {
    block(Block.KIND.prompt, 0),
    block(Block.KIND.message, 2),
    block(Block.KIND.tool, 4, { id = 'a', category = Block.CATEGORY.read, status = Block.STATUS.completed }),
    block(Block.KIND.tool, 6, { id = 'b', category = Block.CATEGORY.edit, status = Block.STATUS.failed }),
    block(Block.KIND.diff, 8, { path = 'f.lua' }),
    block(Block.KIND.prompt, 10),
    block(Block.KIND.tool, 12, { id = 'c', category = Block.CATEGORY.execute, status = Block.STATUS.in_progress }),
  }

  it('lists the rows of each kind', function()
    eq({ 0, 10 }, motions.rows(blocks, 'turn'))
    eq({ 4, 6, 12 }, motions.rows(blocks, 'tool'))
    eq({ 6, 8 }, motions.rows(blocks, 'edit'))
    eq({ 6 }, motions.rows(blocks, 'failed'))
  end)

  it('lists the tools that are waiting for an answer', function()
    eq({ 12 }, motions.rows(blocks, 'waiting', { waiting = { { id = 'c' } } }))
    eq({}, motions.rows(blocks, 'waiting', { waiting = {} }))
  end)

  it('ends on the last line while a question is open', function()
    eq({ 20 }, motions.rows(blocks, 'waiting', { waiting = {}, asks = { {} }, last = 20 }))
    eq({ 12 }, motions.rows(blocks, 'waiting', { waiting = { { id = 'c' } }, asks = { {} }, last = 12 }))
  end)

  it('picks the nth row after or before the cursor', function()
    local rows = { 4, 6, 12 }

    eq(6, motions.pick(rows, 4, 1))
    eq(12, motions.pick(rows, 4, 1, 2))
    assert.is_nil(motions.pick(rows, 12, 1))
    eq(6, motions.pick(rows, 12, -1))
    eq(4, motions.pick(rows, 12, -1, 2))
    assert.is_nil(motions.pick(rows, 4, -1))
  end)
end)

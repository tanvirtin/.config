local Layout = require('harness.transcript.calculators.Layout')

local eq = assert.are.same

local function block(kind, lines)
  return { kind = kind, lines = lines }
end

describe('harness.transcript.calculators.Layout:', function()
  it('places blocks one after another with a blank line between, except a streaming reply', function()
    local list = { block('prompt', { 'hi' }), block('message', { 'a', 'b' }) }

    eq({ 'hi', '', 'a', 'b' }, Layout.place(list, 1, 0))
    eq({ 0, 2 }, { list[1].start, list[1].finish })
    eq({ 2, 4 }, { list[2].start, list[2].finish })
  end)

  it('places from a given block and row, leaving earlier blocks alone', function()
    local list = { block('prompt', { 'hi' }), block('tool', { 'x' }) }

    list[1].start, list[1].finish = 0, 2

    eq({ 'x', '' }, Layout.place(list, 2, 2))
    eq({ 2, 4 }, { list[2].start, list[2].finish })
  end)

  it('finds the first block whose kind or lines changed', function()
    local a, b = block('prompt', { 'hi' }), block('message', { 'x' })

    assert.is_nil(Layout.first_changed({ a, b }, { a, block('message', { 'x' }) }))
    eq(2, Layout.first_changed({ a, b }, { a, block('message', { 'y' }) }))
    eq(2, Layout.first_changed({ a }, { a, b }))
    eq(1, Layout.first_changed({ a }, { block('tool', { 'hi' }) }))
  end)

  it('treats a reply that stops streaming as changed, since it gains its trailing blank', function()
    local reply = block('message', { 'x' })

    eq(1, Layout.first_changed({ reply }, { reply, block('stop', { 'done' }) }))
  end)

  it('finds the block at a row by binary search, falling back to the last block', function()
    local list = { block('prompt', { 'a' }), block('tool', { 'b', 'c' }), block('stop', { 'd' }) }

    Layout.place(list, 1, 0)

    eq(list[1], Layout.block_at(list, 0))
    eq(list[2], Layout.block_at(list, 3))
    eq(list[3], Layout.block_at(list, 5))
    eq(list[3], Layout.block_at(list, 99))
  end)

  it('signs a block by the fields that change its decoration', function()
    local a = { kind = 'tool', status = 'pending' }
    local b = { kind = 'tool', status = 'completed' }

    assert.are_not.equal(Layout.signature(a), Layout.signature(b))
    eq(Layout.signature(a), Layout.signature({ kind = 'tool', status = 'pending', lines = { 'other' } }))
  end)
end)

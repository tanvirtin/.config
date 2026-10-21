local fences = require('harness.transcript.fences')

local eq = assert.are.same

describe('harness.transcript.fences:', function()
  it('makes a fence longer than any backtick run in the content, instead of escaping it', function()
    eq('```', fences.fence_for({ 'plain' }))
    eq('````', fences.fence_for({ 'a', '```lua', 'b', '```' }))
    eq('`````', fences.fence_for({ '  ````' }))
    eq('````', fences.fence_for({ ' ```', '+x' }))
  end)
  it('finds the fenced lines around a line, honouring fence length and kind', function()
    local lines = { 'intro', '````md', '```lua', 'x', '```', '````', '~~~', 'y' }

    eq({ 3, 5 }, { fences.fenced_at(lines, 4) })
    eq({ 3, 5 }, { fences.fenced_at(lines, 3) })
    eq({ 8, 8 }, { fences.fenced_at(lines, 8) })
    assert.is_nil(fences.fenced_at(lines, 1))
  end)

  it('names the marker that would close an unfinished fence', function()
    eq('````', fences.open({ '````md', '```lua' }))
    eq(nil, fences.open({ '```', 'x', '```' }))
  end)
end)

local FoldText = require('harness.ui.FoldText')

local eq = assert.are.same

local function document(blocks, lines)
  return {
    blocks = blocks,
    lines = lines or {},
    block_at = function(_, row)
      for _, block in ipairs(blocks) do
        if row >= block.start and row < block.start + #(block.lines or { '' }) then return block end
      end
    end,
  }
end

describe('harness.ui.FoldText:', function()
  it('counts the tools and replies a sub-agent fold holds', function()
    local blocks = {
      { start = 0, kind = 'tool', depth = 1, lines = { 'a' } },
      { start = 1, kind = 'tool', depth = 1, lines = { 'b' } },
      { start = 2, kind = 'message', depth = 1, lines = { 'c' } },
    }

    eq('2 tools · 1 reply', FoldText(document(blocks)):_children_in(0, 3))
  end)

  it('has no count for a fold that holds something outside a sub-agent', function()
    local blocks = { { start = 0, kind = 'tool', lines = { 'a' } } }

    assert.is_nil(FoldText(document(blocks)):_children_in(0, 1))
  end)

  it('has no rails at the top level', function()
    local blocks = { { start = 0, kind = 'tool', lines = { 'a', 'b', 'c' } } }

    eq('  ', FoldText(document(blocks)):_rails(0, 2))
  end)

  it('summarises hidden lines when no child is counted, in the muted group', function()
    local blocks = { { start = 0, kind = 'tool', lines = { 'a', 'b', 'c', 'd' } } }
    local text = FoldText(document(blocks, { 'a', 'b', 'c', 'd' })):text(2, 4)

    eq('UiMuted', text[1][2])
    eq('UiMuted', text[2][2])
    assert.truthy(text[2][1]:find('3 more lines', 1, true))
  end)
end)

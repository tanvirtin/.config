local FoldCalculator = require('harness.transcript.calculators.FoldCalculator')

local eq = assert.are.same

describe('harness.transcript.calculators.FoldCalculator:', function()
  it('opens a fold at each block fold range and keeps other rows unfolded', function()
    local blocks = { { start = 0, finish = 6, folds = { { 1, 3 } }, index = 1 } }

    eq('0', FoldCalculator.level(blocks, 0))
    eq('>1', FoldCalculator.level(blocks, 1))
    eq('1', FoldCalculator.level(blocks, 3))
    eq('0', FoldCalculator.level(blocks, 4))
  end)

  it('folds a nested run under its first block, and nests the block folds one deeper', function()
    local blocks = {
      { start = 0, finish = 2, index = 1 },
      { start = 2, finish = 6, depth = 1, parent = 't', folds = { { 2, 3 } }, index = 2 },
      { start = 6, finish = 8, depth = 1, parent = 't', index = 3 },
    }

    eq('0', FoldCalculator.level(blocks, 0))
    eq('>1', FoldCalculator.level(blocks, 2))
    eq('1', FoldCalculator.level(blocks, 3))
    eq('>2', FoldCalculator.level(blocks, 4))
    eq('2', FoldCalculator.level(blocks, 5))
    eq('1', FoldCalculator.level(blocks, 6))
  end)

  it('leaves rows outside every block unfolded', function()
    eq('0', FoldCalculator.level({ { start = 0, finish = 2, index = 1 } }, 5))
    eq('0', FoldCalculator.level({}, 0))
  end)
end)

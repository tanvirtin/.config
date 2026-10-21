local Layout = require('harness.transcript.calculators.Layout')

local FoldCalculator = {}

function FoldCalculator.level(blocks, row)
  local block = Layout.block_at(blocks, row)

  if not block or row < block.start or row >= block.finish then return '0' end

  local base = block.depth or 0

  for _, fold in ipairs(block.folds or {}) do
    local from, to = block.start + fold[1], block.start + fold[2]

    if to > from then
      if row == from then return '>' .. (base + 1) end
      if row > from and row <= to then return tostring(base + 1) end
    end
  end

  if base > 0 then
    local previous = block.index and blocks[block.index - 1]
    local opens = not previous or previous.parent ~= block.parent

    if opens and row == block.start then return '>' .. base end

    return tostring(base)
  end

  return '0'
end

return FoldCalculator

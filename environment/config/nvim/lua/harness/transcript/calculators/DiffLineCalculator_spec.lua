local DiffLineCalculator = require('harness.transcript.calculators.DiffLineCalculator')

local eq = assert.are.same

local function diff(lines)
  local out = { '```diff', '+++ a.lua' }

  vim.list_extend(out, lines)
  out[#out + 1] = '```'

  return { path = 'a.lua', start = 10, lines = out }
end

describe('harness.transcript.calculators.DiffLineCalculator:', function()
  it('numbers each diff line from its hunk header, old side for removals, new side otherwise', function()
    local numbers = DiffLineCalculator.numbers(diff({ '@@ -4,2 +4,3 @@', ' a', '-b', '+c', '+d' }).lines)

    eq({ mark = '@' }, numbers[3])
    eq(4, numbers[4].number)
    eq({ '-', 5 }, { numbers[5].mark, numbers[5].number })
    eq({ '+', 5 }, { numbers[6].mark, numbers[6].number })
    eq({ '+', 6 }, { numbers[7].mark, numbers[7].number })
  end)

  it('finds where the new side sits in the file, so numbers survive a stale hunk header', function()
    local block = diff({ '@@ -1,2 +1,2 @@', ' a', '+c' })
    local file = { 'x', 'y', 'a', 'c' }
    local offset = DiffLineCalculator.offset(block, function()
      return file
    end, {})

    eq(2, offset)
    eq(4, DiffLineCalculator.line(block, block.start + 4, offset))
  end)

  it('falls back to the old side when the edit is not in the file yet', function()
    local block = diff({ '@@ -1,2 +1,2 @@', ' a', '-b', '+c' })

    eq(
      0,
      DiffLineCalculator.offset(block, function()
        return { 'a', 'b' }
      end)
    )
  end)

  it('caches a found new side, reading the file once', function()
    local block = diff({ '@@ -1 +1 @@', '+c' })
    local reads, cache = 0, {}
    local function file_lines()
      reads = reads + 1
      return { 'c' }
    end

    DiffLineCalculator.offset(block, file_lines, cache)
    DiffLineCalculator.offset(block, file_lines, cache)

    eq(1, reads)
  end)

  it('has no offset without a path or a match', function()
    assert.is_nil(DiffLineCalculator.offset({ lines = {} }, function()
      return {}
    end))
    assert.is_nil(DiffLineCalculator.offset(diff({ '@@ -1 +1 @@', '+zzz' }), function()
      return { 'a' }
    end))
  end)
end)

local search = require('sn.picker.search')

local eq = assert.are.same

describe('sn.picker.search:', function()
  it('finds a query as one run when it can, and as a spread of letters when it must', function()
    local score, positions = search.find('Fix the scroll pin', 'scroll')

    assert.is_true(score > 40)
    eq({ 9, 10, 11, 12, 13, 14 }, positions)

    local spread, at = search.find('Fix the scroll pin', 'fsp')

    assert.is_true(spread < score)
    eq({ 1, 9, 16 }, at)
    assert.is_nil(search.find('Fix the scroll pin', 'zzz'))
  end)

  it('ignores case, and matches everything for an empty query', function()
    assert.is_truthy(search.find('Fix', 'FIX'))
    eq({}, select(2, search.find('anything', '')))
  end)

  it('prefers whole words and earlier matches', function()
    local word = search.find('fix the pin', 'pin')
    local inside = search.find('mapping', 'pin')
    local late = search.find(string.rep('x ', 30) .. 'pin', 'pin')

    assert.is_true(word > inside)
    assert.is_true(word > late)
  end)

  it('ranks label matches over description, and description over the transcript', function()
    local rows = {
      { label = 'other', description = 'about scroll', id = 'description' },
      { label = 'something', description = 'nope', id = 'corpus' },
      { label = 'scroll pin', description = '', id = 'label' },
      { label = 'nothing', description = 'nothing', id = 'none' },
    }
    local ranked = search.rank(rows, 'scroll', function(row)
      return row.id == 'corpus' and 'we talked about scroll earlier' or ''
    end)

    eq(
      { 'label', 'description', 'corpus' },
      vim.tbl_map(function(row)
        return row.id
      end, ranked)
    )
    eq({ 1, 2, 3, 4, 5, 6 }, rows[3].match)
    assert.is_nil(rows[1].match)
  end)

  it('keeps the order it was given for equal scores, and clears matches for an empty query', function()
    local rows = { { label = 'a one' }, { label = 'a two' } }

    eq(rows, search.rank(rows, '', nil))
    eq(
      { 'a one', 'a two' },
      vim.tbl_map(function(row)
        return row.label
      end, search.rank(rows, 'a', nil))
    )
    assert.is_nil(rows[1].match and nil)
  end)
end)

local text = require('core.text')

local eq = assert.are.same

describe('core.text:', function()
  it('splits a string into its characters, whole even when they are many bytes', function()
    eq({ 'a', '▓', 'b' }, text.chars('a▓b'))
    eq({}, text.chars(''))
  end)

  it('sums the width of highlighted chunks', function()
    eq(4, text.width_of({ { 'ab' }, { 'cd' } }))
    eq(1, text.width_of({ { '▓' } }))
    eq(0, text.width_of({}))
  end)

  it('formats ages coarsely', function()
    eq('just now', text.ago(4999))
    eq('5s ago', text.ago(5000))
    eq('2m ago', text.ago(120000))
    eq('2h ago', text.ago(7200000))
    eq('2d ago', text.ago(172800000))
  end)

  describe('fuzzy', function()
    it('keeps only the items whose key matches the query', function()
      local items = { { name = 'buffer_edit' }, { name = 'git_diff' }, { name = 'buffer_read' } }

      local found = text.fuzzy(items, 'gitdif', function(item)
        return item.name
      end)

      eq(
        { 'git_diff' },
        vim.tbl_map(function(item)
          return item.name
        end, found)
      )
    end)
  end)
end)

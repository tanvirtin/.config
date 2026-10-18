local compact = require('compact')

local eq = assert.are.same

local function at(path, line, text, col)
  return { path = vim.fn.getcwd() .. '/' .. path, line = line, col = col, text = text }
end

describe('compact:', function()
  describe('line', function()
    it('collapses whitespace and trims to a width', function()
      eq('local x = 1', compact.line('  local   x =\t1  '))
      eq('abcd…', compact.line('abcdefgh', 5))
      eq('', compact.line(nil))
    end)
  end)

  describe('locations', function()
    it('groups by file with relative paths, in order, sorted by line', function()
      local text, info = compact.locations({
        at('a.lua', 9, 'second'),
        at('b.lua', 1, 'other'),
        at('a.lua', 2, '  first  ', 5),
      })

      eq('a.lua (2)\n  2:5: first\n  9: second\nb.lua (1)\n  1: other', text)
      eq({ shown = 3, total = 3 }, info)
    end)

    it('joins duplicate lines', function()
      local text = compact.locations({ at('a.lua', 3, 'x'), at('a.lua', 3, 'x') })

      eq('a.lua (2)\n  3: x', text)
    end)

    it('stops at the budget and says how to get the rest', function()
      local items = {}

      for i = 1, 50 do
        items[i] = at(i <= 25 and 'a.lua' or 'b.lua', i, string.rep('y', 40))
      end

      local text, info = compact.locations(items, { budget = 300 })
      local hidden = 50 - info.shown

      assert.is_true(#text < 420)
      assert.is_truthy(text:find('… ' .. hidden .. ' more in 2 files %(offset=' .. info.shown .. '%)$'))

      local rest, rest_info = compact.locations(items, { offset = info.shown, budget = 100000 })

      eq(hidden, rest_info.shown)
      assert.is_falsy(rest:find('more', 1, true))
    end)

    it('says when there is nothing', function()
      eq('no results', (compact.locations({})))
      eq('Refs (0)\nnone', (compact.locations({}, { title = 'Refs', empty = 'none' })))
    end)
  end)

  describe('rows', function()
    it('aligns cells under a header and stops at the budget', function()
      eq('name | n\na | 1\nb | ', compact.rows({ { name = 'a', n = 1 }, { name = 'b' } }, { 'name', 'n' }))

      local many = {}
      for i = 1, 100 do
        many[i] = { name = 'row' .. i }
      end

      assert.is_truthy(compact.rows(many, { 'name' }, { budget = 50 }):find('more rows %(offset=%d+%)$'))
    end)
  end)

  describe('text', function()
    it('keeps the head and tail of long text', function()
      local lines = {}
      for i = 1, 200 do
        lines[i] = 'line ' .. i
      end

      local out = compact.text(table.concat(lines, '\n'), 300)

      assert.is_truthy(out:find('^line 1\n'))
      assert.is_truthy(out:find('line 200$'))
      assert.is_truthy(out:find('lines omitted', 1, true))
      eq('short', compact.text('short', 300))
    end)
  end)

  describe('stats', function()
    before_each(function()
      compact.reset_stats()
    end)

    it('measures each reply against the raw JSON, per caller', function()
      local raw = { { path = string.rep('p', 400), line = 1 } }

      eq('short', compact.reply('h1', raw, 'short'))
      compact.reply('h2', 'abcd', 'ab')

      local one = compact.stats('h1')

      eq(1, one.calls)
      assert.is_true(one.raw_tokens > 100)
      eq(2, one.tokens)
      assert.is_true(one.saved_tokens > 90)
      eq(2, compact.stats().calls)
    end)
  end)
end)

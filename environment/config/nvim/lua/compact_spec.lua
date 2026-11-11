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

  describe('excerpts', function()
    local FILE = { 'one', '  two', 'three', 'four', 'five', 'six', 'seven', 'eight' }

    local function excerpts(items, opts)
      return compact.excerpts(
        items,
        vim.tbl_extend('force', {
          context = 1,
          lines_of = function()
            return FILE
          end,
        }, opts or {})
      )
    end

    it('shows the lines around each match, marking the matches and keeping indentation', function()
      eq(
        '/x/a.lua (1)\n  1- one\n  2:   two\n  3- three',
        (excerpts({ { path = '/x/a.lua', line = 2, text = '  two' } }))
      )
    end)

    it('joins matches whose lines touch, and marks a gap between ones that do not', function()
      eq(
        '/x/a.lua (3)\n  1- one\n  2:   two\n  3: three\n  4- four\n  …\n  6- six\n  7: seven\n  8- eight',
        (
          excerpts({
            { path = '/x/a.lua', line = 2 },
            { path = '/x/a.lua', line = 3 },
            { path = '/x/a.lua', line = 7 },
          })
        )
      )
    end)

    it('stops at the budget and says where to continue', function()
      local text, counts = excerpts({
        { path = '/x/a.lua', line = 2 },
        { path = '/x/a.lua', line = 7 },
      }, { budget = 40 })

      eq({ shown = 1, total = 2 }, counts)
      assert.is_truthy(text:find('… 1 more (offset=1)', 1, true))
      assert.is_truthy(excerpts({
        { path = '/x/a.lua', line = 2 },
        { path = '/x/a.lua', line = 7 },
      }, { offset = 1 }):find('7: seven', 1, true))
    end)

    it('falls back to the matched text when the file cannot be read', function()
      eq('/x/a.lua (1)\n  2: found', (excerpts({ { path = '/x/a.lua', line = 2, text = 'found' } }, {
        lines_of = function()
          return nil
        end,
      })))
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

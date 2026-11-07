local symbols = require('harness.symbols')

local eq = assert.are.same

local SOURCE = {
  'local Session = {}',
  '',
  'function Session:refresh()',
  '  return token.expiry()',
  'end',
  '',
  'local function helper()',
  '  return 1',
  'end',
  '',
  'function Session.close()',
  'end',
}

describe('harness.symbols:', function()
  it('names the functions in a file and the lines each spans', function()
    eq({
      { name = 'Session:refresh', first = 3, last = 5 },
      { name = 'helper', first = 7, last = 9 },
      { name = 'Session.close', first = 11, last = 12 },
    }, symbols.parse(SOURCE, 'a.lua'))
  end)

  it('finds a symbol by its full name or by an unambiguous last part, whatever the separator', function()
    local list = symbols.parse(SOURCE, 'a.lua')

    eq(3, symbols.find(list, 'Session:refresh').first)
    eq(3, symbols.find(list, 'Session.refresh').first)
    eq(11, symbols.find(list, 'close').first)
    eq({ nil, 'no symbol nope' }, { symbols.find(list, 'nope') })
  end)

  it('names every candidate when a short name matches several', function()
    local list = {
      { name = 'A.run', first = 1, last = 2 },
      { name = 'B.run', first = 3, last = 4 },
    }

    eq({ nil, 'run is ambiguous: A.run, B.run' }, { symbols.find(list, 'run') })
  end)

  it('picks the innermost symbol around a range', function()
    local list = {
      { name = 'Outer', first = 1, last = 20 },
      { name = 'Outer.inner', first = 5, last = 8 },
    }

    eq('Outer.inner', symbols.enclosing(list, 6, 7).name)
    eq('Outer', symbols.enclosing(list, 4, 7).name)
    eq(nil, symbols.enclosing(list, 30, 31))
  end)

  it('has nothing to say about a file it cannot parse', function()
    eq({}, symbols.parse({ 'whatever' }, 'notes.unknownext'))
  end)
end)

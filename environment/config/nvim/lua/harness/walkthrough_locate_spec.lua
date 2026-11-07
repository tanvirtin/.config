local walkthrough_locate = require('harness.walkthrough_locate')

local eq = assert.are.same

local FILE = {
  'local Session = {}',
  '',
  'function Session:refresh()',
  '  return 1',
  'end',
}

describe('harness.walkthrough_locate:', function()
  local read_from
  local env = {
    dir = '/w',
    read = function(path)
      read_from = path

      return path == '/w/a.lua' and FILE or nil
    end,
    scope = {
      by_id = { h2 = { file = { absolute = '/w/b.lua' }, hunk = { first = 4, last = 9 } } },
    },
  }

  it('turns a hunk id into the lines it changed', function()
    eq({ path = '/w/b.lua', line = 4, end_line = 9 }, walkthrough_locate.resolve('h2', env))
    eq({ nil, 'no hunk h7' }, { walkthrough_locate.resolve('h7', env) })
  end)

  it('asks for walkthrough_scope when a hunk id comes without one', function()
    local _, err = walkthrough_locate.resolve('h1', { dir = '/w', read = env.read })

    assert.truthy(err:find('call it first', 1, true))
  end)

  it('takes lines as path:from-to or path:line, without reading the file', function()
    read_from = nil

    eq({ path = 'a.lua', line = 3, end_line = 5 }, walkthrough_locate.resolve('a.lua:3-5', env))
    eq({ path = 'a.lua', line = 4, end_line = 4 }, walkthrough_locate.resolve('a.lua:4', env))
    eq(nil, read_from)
  end)

  it('finds a symbol by name, so the agent need not read the file for line numbers', function()
    eq({ path = 'a.lua', line = 3, end_line = 5 }, walkthrough_locate.resolve('a.lua:Session:refresh', env))
    eq({ path = 'a.lua', line = 3, end_line = 5 }, walkthrough_locate.resolve('a.lua:refresh', env))
    eq('/w/a.lua', read_from)
    eq({ nil, 'a.lua: no symbol close' }, { walkthrough_locate.resolve('a.lua:close', env) })
  end)

  it('takes a bare path as the whole file', function()
    eq({ path = 'a.lua', line = 1, end_line = 5 }, walkthrough_locate.resolve('a.lua', env))
    eq({ nil, 'no file nope.lua' }, { walkthrough_locate.resolve('nope.lua:run', env) })
  end)

  it('resolves a list, naming which entry failed', function()
    eq(2, #walkthrough_locate.ranges({ 'h2', 'a.lua:1' }, env))
    eq({ nil, 'at 2: no hunk h9' }, { walkthrough_locate.ranges({ 'h2', 'h9' }, env) })
    eq({ nil, 'a step needs at' }, { walkthrough_locate.ranges({}, env) })
  end)
end)

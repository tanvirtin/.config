local walkthrough_diagram = require('harness.walkthrough_diagram')

local eq = assert.are.same

local SOURCE = {
  'local M = {}',
  '',
  'function M.refresh()',
  '  local t = M.expiry()',
  '  return http.post(t)',
  'end',
  '',
  'function M.expiry()',
  '  return 1',
  'end',
  '',
  'function M.login()',
  '  return M.refresh()',
  'end',
}

local function item(name, where, line)
  return { name = name, where = where, target = { path = '/w/a.lua', line = line, last = line } }
end

describe('harness.walkthrough_diagram:', function()
  it('draws callers into a box for the function and its calls out of it, each row opening its code', function()
    local center = item('M.refresh', 'a.lua:3', 3)
    local view = walkthrough_diagram.render(
      center,
      { item('M.login', 'a.lua:13', 13), item('main', 'cli.lua:40', 40) },
      { item('M.expiry', 'a.lua:8', 8), item('http.post', 'elsewhere') }
    )

    eq({
      'M.login  a.lua:13   ─┐',
      'main     cli.lua:40 ─┤',
      '                     ▼',
      '               ╭───────────╮',
      '               │ M.refresh │  a.lua:3',
      '               ╰───────────╯',
      '                     │',
      '                     ├─▶ M.expiry   a.lua:8',
      '                     └─▶ http.post  elsewhere',
    }, view.lines)
    eq(center.target, view.targets[5])
    eq(13, view.targets[1].line)
    eq(8, view.targets[8].line)
  end)

  it('says so when nothing calls in or out, and caps a long list', function()
    local saved = walkthrough_diagram.MAX_ITEMS
    local view = walkthrough_diagram.render(item('lonely', 'a.lua:1', 1), {}, {})

    eq({
      '╭────────╮',
      '│ lonely │  a.lua:1',
      '╰────────╯',
      '',
      'Nothing calls it and it calls nothing, as far as can be seen.',
    }, view.lines)

    walkthrough_diagram.MAX_ITEMS = 1
    view = walkthrough_diagram.render(item('f', 'a.lua:1', 1), {}, { item('a', 'x', 1), item('b', 'y', 2) })
    walkthrough_diagram.MAX_ITEMS = saved

    eq('  └─ … 1 more', view.lines[#view.lines])
  end)

  it('reads the calls in and out of a function from the file when no language server is there', function()
    local result

    walkthrough_diagram.collect({ lines = SOURCE, path = '/w/a.lua', first = 4, last = 4 }, function(found)
      result = found
    end)

    eq('M.refresh', result.center.name)
    eq(
      { { 'M.login', 'a.lua:13' } },
      vim.tbl_map(function(each)
        return { each.name, each.where }
      end, result.callers)
    )
    eq(
      { { 'M.expiry', 'a.lua:8' }, { 'http.post', 'elsewhere' } },
      vim.tbl_map(function(each)
        return { each.name, each.where }
      end, result.callees)
    )
    assert.truthy(result.note:find('no language server', 1, true))
  end)

  it('does not take a method of another object for one in this file', function()
    local lines = { 'local M = {}', 'function M.prompt() end', 'function M.run()', '  self.session:prompt()', 'end' }
    local result

    walkthrough_diagram.collect({ lines = lines, path = '/w/a.lua', first = 4, last = 4 }, function(found)
      result = found
    end)

    eq({ 'self.session:prompt', 'elsewhere' }, { result.callees[1].name, result.callees[1].where })
  end)

  it('asks the language server for callers and callees when one can answer', function()
    local lsp = require('core.lsp')
    local saved = { supports = lsp.supports, uri = lsp.uri, request = lsp.request, path = lsp.path }
    local asked = {}

    local function entry(name, line)
      local range = { start = { line = line - 1, character = 0 }, ['end'] = { line = line + 1, character = 3 } }

      return { name = name, uri = 'file:///w/b.lua', range = range, selectionRange = range }
    end

    local results = {
      [walkthrough_diagram.PREPARE] = { entry('M.refresh', 3) },
      ['callHierarchy/incomingCalls'] = { { from = entry('server.handle', 12) } },
      ['callHierarchy/outgoingCalls'] = { { to = entry('db.get', 40) } },
    }

    lsp.supports = function(_, method)
      return method == walkthrough_diagram.PREPARE
    end
    lsp.uri = function()
      return 'file:///w/a.lua'
    end
    lsp.path = function(uri)
      return uri:gsub('^file://', '')
    end
    lsp.request = function(_, method, params, done)
      asked[#asked + 1] = { method, params.position }
      done(results[method])
    end

    local result

    walkthrough_diagram.collect({ bufnr = 1, lines = SOURCE, path = '/w/a.lua', first = 4, last = 4 }, function(found)
      result = found
    end)

    for name, fn in pairs(saved) do
      lsp[name] = fn
    end

    eq({ line = 2, character = 9 }, asked[1][2])
    eq({ 'server.handle', 'b.lua:12' }, { result.callers[1].name, result.callers[1].where })
    eq({ 'db.get', 'b.lua:40', '/w/b.lua', 40 }, {
      result.callees[1].name,
      result.callees[1].where,
      result.callees[1].target.path,
      result.callees[1].target.line,
    })
    eq(nil, result.note)
  end)

  it('falls back to the file when the language server finds nothing at the function', function()
    local lsp = require('core.lsp')
    local saved = { supports = lsp.supports, uri = lsp.uri, request = lsp.request }
    local result

    lsp.supports = function()
      return true
    end
    lsp.uri = function()
      return 'file:///w/a.lua'
    end
    lsp.request = function(_, _, _, done)
      done({})
    end

    walkthrough_diagram.collect({ bufnr = 1, lines = SOURCE, path = '/w/a.lua', first = 4, last = 4 }, function(found)
      result = found
    end)

    for name, fn in pairs(saved) do
      lsp[name] = fn
    end

    eq('M.login', result.callers[1].name)
    assert.truthy(result.note:find('no language server', 1, true))
  end)

  it('says when the step is not inside a function', function()
    local found, err

    walkthrough_diagram.collect({ lines = SOURCE, path = '/w/a.lua', first = 1, last = 1 }, function(result, why)
      found, err = result, why
    end)

    eq(nil, found)
    eq('no function around this step to draw', err)
  end)
end)

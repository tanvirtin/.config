local Buffer = require('core.Buffer')
local outline = require('nvim_mcp.outline')

local eq = assert.are.same

local function entries(filetype, lines)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype

  return outline.of(Buffer(buf):syntax_root(), buf, lines)
end

describe('nvim_mcp.outline:', function()
  local LUA = {
    'local M = {}',
    '',
    'local function helper(a)',
    '  return a',
    'end',
    '',
    'function M.run(a)',
    '  local inner = function(b)',
    '    return b',
    '  end',
    '',
    '  return inner(a)',
    'end',
    '',
    'local short = function() end',
    '',
    'describe(\'thing\', function()',
    '  return 1',
    'end)',
  }

  it('lists the definitions that span lines, nested, with their first line', function()
    eq(
      table.concat({
        '3-5 local function helper(a)',
        '7-13 function M.run(a)',
        '  8-10 local inner = function(b)',
        '17-19 describe(\'thing\', function()',
      }, '\n'),
      outline.format(entries('lua', LUA))
    )
  end)

  it('names a definition when the grammar does', function()
    local found = entries('lua', LUA)

    eq('helper', found[1].name)
    eq('M.run', found[2].name)
    eq(nil, found[3].name)
  end)

  it('finds a definition by its name, its last part, or its first line', function()
    local found = entries('lua', LUA)

    eq({ found[1] }, outline.find(found, 'helper'))
    eq({ found[2] }, outline.find(found, 'run'))
    eq({ found[3] }, outline.find(found, 'inner'))
    eq({}, outline.find(found, 'nope'))
  end)

  it('prefers an exact name to a longer one that ends with it', function()
    local found = entries('lua', {
      'function M.run()',
      '  return 1',
      'end',
      '',
      'local function run()',
      '  return 2',
      'end',
    })

    eq({ found[2] }, outline.find(found, 'run'))
  end)

  it('outlines markdown by section', function()
    eq(
      '1-7 # Title\n  5-7 ## Part',
      outline.format(entries('markdown', { '# Title', '', 'text', '', '## Part', '', 'more' }))
    )
  end)

  it('says when there is nothing to list', function()
    eq('no definitions', outline.format(entries('lua', { 'return 1' })))
  end)
end)

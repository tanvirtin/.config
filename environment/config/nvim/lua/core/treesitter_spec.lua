local treesitter = require('core.treesitter')

local eq = assert.are.same

local TEXT = '# Title\n'

local function headings()
  local query = treesitter.parse_query('markdown', '(atx_heading) @heading')
  local parser = treesitter.string_parser(TEXT, 'markdown')
  local found = {}

  for id, node in query:iter_captures(parser:parse()[1]:root(), TEXT, 0, 1) do
    found[#found + 1] = { name = query.captures[id], node = node }
  end

  return found
end

describe('core.treesitter:', function()
  it('compiles a query and finds its capture in a parsed string', function()
    local found = headings()

    eq(
      { 'heading' },
      vim.tbl_map(function(capture)
        return capture.name
      end, found)
    )
  end)

  it('reads the text and the range of a node', function()
    local node = headings()[1].node

    eq('atx_heading', node:type())
    eq('# Title', vim.trim(treesitter.node_text(node, TEXT)))
    eq(0, treesitter.range(node, TEXT)[1])
  end)

  it('finds the highlight query files of a language, and a language for a filetype', function()
    assert.is_true(#treesitter.query_files('markdown', 'highlights') > 0)
    eq('markdown', treesitter.language_of('markdown'))
    assert.is_truthy(treesitter.query('markdown', 'highlights'))
  end)

  it('does not load a language that is not installed', function()
    local ok, loaded = pcall(treesitter.add_language, 'no_such_language_anywhere')

    assert.is_false(ok and loaded and true or false)
  end)
end)

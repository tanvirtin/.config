local table_layout = require('ui.markdown.table')

local eq = assert.are.same

local function text(line)
  return table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, line))
end

describe('ui.markdown.table:', function()
  it('draws a boxed table sized by the widest cell of each column', function()
    local lines = table_layout.lines({ 'a', 'bb' }, { { 'ccc', 'd' } }, {})

    eq({
      '┌─────┬────┐',
      '│ a   │ bb │',
      '├─────┼────┤',
      '│ ccc │ d  │',
      '└─────┴────┘',
    }, vim.tbl_map(text, lines))
  end)

  it('aligns cells right and centre, measuring display width', function()
    local A = table_layout.ALIGN
    local lines = table_layout.lines({ 'n', 'name' }, { { '7', '日本' }, { '10', 'x' } }, { A.right, A.center })

    eq('│  7 │ 日本 │', text(lines[4]))
    eq('│ 10 │  x   │', text(lines[5]))
  end)

  it('fills missing cells and draws a header-only table', function()
    eq(
      { '┌───┬───┐', '│ a │ b │', '└───┴───┘' },
      vim.tbl_map(text, table_layout.lines({ 'a', 'b' }, {}, {}))
    )
    eq('│ x │   │', text(table_layout.lines({ 'a', 'b' }, { { 'x' } }, {})[4]))
  end)

  it('colours borders, the header and cells apart', function()
    local lines = table_layout.lines({ 'a' }, { { 'b' } }, {})

    eq(table_layout.HL.border, lines[1][1][2])
    eq(table_layout.HL.header, lines[2][2][2])
    eq(table_layout.HL.cell, lines[4][2][2])
  end)
end)

local Table = require('ui.content.table')

local eq = assert.are.same

local function rows(marks)
  local out = {}

  for _, mark in ipairs(marks) do
    if mark.opts.virt_text then out[mark.row] = mark.opts.virt_text[1][1] end
  end

  return out
end

describe('ui.content.table:', function()
  it('should align CSV rows under a header', function()
    local marks = Table.render({
      kind = 'tool',
      lang = 'csv',
      start = 10,
      lines = { '-> cat a.csv', '```output_csv', 'name,age', 'Ada,36', 'Bob,7', '```' },
    }, { first = 3, trim = 1 }, { width = 80 })

    eq({ [12] = 'name │ age', [13] = 'Ada  │ 36 ', [14] = 'Bob  │ 7  ' }, rows(marks))
  end)

  it('should handle quoted cells and TSV', function()
    local marks = Table.render({
      kind = 'tool',
      lang = 'csv',
      start = 0,
      lines = { '-> cat a.csv', '```output_csv', 'name,note', '"Ada, A.",ok', '```' },
    }, { first = 3, trim = 1 }, { width = 80 })

    eq({ [2] = 'name    │ note', [3] = 'Ada, A. │ ok  ' }, rows(marks))

    marks = Table.render({
      kind = 'tool',
      lang = 'tsv',
      start = 0,
      lines = { '-> cat a.tsv', '```output_tsv', 'name\tage', 'Ada\t36', '```' },
    }, { first = 3, trim = 1 }, { width = 80 })

    eq({ [2] = 'name │ age', [3] = 'Ada  │ 36 ' }, rows(marks))
  end)
end)

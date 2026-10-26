local Table = require('ui.content.table')
local content = require('harness.transcript.content')
local hit_test = require('harness.ui.hit_test')
local builtin = require('harness.transcript.content.builtin')

local eq = assert.are.same

local function rows(marks)
  local out = {}

  for _, mark in ipairs(marks) do
    if mark.opts.virt_text then out[mark.row] = mark.opts.virt_text[1][1] end
  end

  return out
end

describe('ui.content.table:', function()
  before_each(function()
    content.reset()
    builtin()
  end)

  after_each(function()
    content.reset()
    builtin()
  end)

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

  it('should hit-test CSV and TSV cells by raw columns', function()
    local block = {
      kind = 'tool',
      lang = 'csv',
      start = 10,
      lines = { '-> cat a.csv', '```output_csv', 'name,age', 'Ada,36', '```' },
    }

    eq({ text = 'Ada', group = 'table_cell' }, hit_test.at(block, 13, 0))
    eq({ text = '36', group = 'table_cell' }, hit_test.at(block, 13, 4))
    assert.is_nil(hit_test.at(block, 13, 3))

    block = {
      kind = 'tool',
      lang = 'tsv',
      start = 0,
      lines = { '-> cat a.tsv', '```output_tsv', 'name\tage', 'Ada\t36', '```' },
    }

    eq({ text = '36', group = 'table_cell' }, hit_test.at(block, 3, 4))
  end)
end)

local MarkSpec = require('harness.transcript.MarkSpec')

local eq = assert.are.same

describe('harness.transcript.MarkSpec:', function()
  it('adds a mark with the default priority unless one is given', function()
    local out = {}

    MarkSpec.add(out, 1, 2, { hl_group = 'X' })
    MarkSpec.add(out, 3, 0, { hl_group = 'Y', priority = 10 })

    eq({ 1, 2, MarkSpec.PRIORITY }, { out[1].row, out[1].col, out[1].opts.priority })
    eq(10, out[2].opts.priority)
  end)

  it('requires a row, a column and options', function()
    assert.has_error(function()
      MarkSpec({ row = 1, col = 0 })
    end)
  end)
end)

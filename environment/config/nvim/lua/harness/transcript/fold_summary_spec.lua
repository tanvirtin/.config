local fold_summary = require('harness.transcript.fold_summary')

local eq = assert.are.same

describe('harness.transcript.fold_summary:', function()
  it('previews the first line with something on it, skipping blanks and fences', function()
    eq('error: boom', fold_summary.preview({ '', '```output', '  error: boom  ', 'next' }))
  end)

  it('previews from the end for command output, where the result is', function()
    eq('PASSED 3 tests', fold_summary.preview({ 'running', 'PASSED 3 tests', '```' }, nil, true))
    eq('2 more lines · "ok"', fold_summary.text('2 more lines', { 'running', 'ok' }, false, true))
  end)

  it('has no preview for blank lines', function()
    eq(nil, (fold_summary.preview({ '', '  ' })))
  end)

  it('cuts a long preview', function()
    assert.is_true(vim.fn.strchars(fold_summary.preview({ string.rep('x', 200) }, 20)) <= 20)
  end)

  it('counts the hidden lines, flags a failure and quotes the preview', function()
    eq('42 more lines · failed · "error: x"', fold_summary.text('42 more lines', { 'error: x' }, true))
    eq('3 more lines', fold_summary.text('3 more lines', { '' }, false))
  end)
end)

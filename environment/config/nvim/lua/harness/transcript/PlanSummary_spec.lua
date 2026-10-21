local PlanSummary = require('harness.transcript.PlanSummary')

local eq = assert.are.same

local ENTRIES = {
  { content = 'read', status = 'completed' },
  { content = 'edit', status = 'in_progress' },
  { content = 'test', status = 'pending' },
}

describe('harness.transcript.PlanSummary:', function()
  it('finds the latest plan in the history', function()
    local history = {
      { kind = 'plan', entries = { { content = 'old' } } },
      { kind = 'message', text = 'x' },
      { kind = 'plan', entries = ENTRIES },
    }

    eq(ENTRIES, PlanSummary.latest(history))
    assert.is_nil(PlanSummary.latest({ { kind = 'message', text = 'x' } }))
  end)

  it('counts finished entries and knows when a plan is still open', function()
    eq(1, PlanSummary.done(ENTRIES))
    assert.is_true(PlanSummary.unfinished(ENTRIES))
    assert.is_false(PlanSummary.unfinished({ { content = 'a', status = 'completed' } }))
    assert.is_false(PlanSummary.unfinished({}))
  end)

  it('renders a titled checklist marked by status, muting what is done', function()
    local summary = PlanSummary.render(ENTRIES)

    eq(' Plan  1/3', summary.lines[1])
    eq(' ✓ read', summary.lines[2])
    eq(' ◆ edit', summary.lines[3])
    eq(' ○ test', summary.lines[4])
    eq('UiTitle', summary.highlights[1].hl)
    eq(2, #vim.tbl_filter(function(highlight)
      return highlight.row == 1
    end, summary.highlights))
    assert.is_true(summary.width > #' Plan  1/3')
  end)

  it('clips long entries to the panel width', function()
    local summary = PlanSummary.render({ { content = string.rep('x', 200) } })

    assert.is_true(vim.fn.strdisplaywidth(summary.lines[2]) <= PlanSummary.MAX_WIDTH)
  end)
end)

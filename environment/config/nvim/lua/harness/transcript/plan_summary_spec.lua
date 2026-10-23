local plan_summary = require('harness.transcript.plan_summary')

local eq = assert.are.same

local ENTRIES = {
  { content = 'read', status = 'completed' },
  { content = 'edit', status = 'in_progress' },
  { content = 'test', status = 'pending' },
}

describe('harness.transcript.plan_summary:', function()
  it('finds the latest plan in the history', function()
    local history = {
      { kind = 'plan', entries = { { content = 'old' } } },
      { kind = 'message', text = 'x' },
      { kind = 'plan', entries = ENTRIES },
    }

    eq(ENTRIES, plan_summary.latest(history))
    assert.is_nil(plan_summary.latest({ { kind = 'message', text = 'x' } }))
  end)

  it('counts finished entries and knows when a plan is still open', function()
    eq(1, plan_summary.done(ENTRIES))
    assert.is_true(plan_summary.unfinished(ENTRIES))
    assert.is_false(plan_summary.unfinished({ { content = 'a', status = 'completed' } }))
    assert.is_false(plan_summary.unfinished({}))
  end)

  it('renders a titled checklist marked by status, muting what is done', function()
    local summary = plan_summary.render(ENTRIES)

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
    local summary = plan_summary.render({ { content = string.rep('x', 200) } })

    assert.is_true(vim.fn.strdisplaywidth(summary.lines[2]) <= plan_summary.MAX_WIDTH)
  end)
end)

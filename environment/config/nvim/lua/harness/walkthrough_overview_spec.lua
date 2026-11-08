local walkthrough_overview = require('harness.walkthrough_overview')

local eq = assert.are.same

local function hunk(id, path, first, last, added, removed)
  return { id = id, path = path, first = first, last = last, added = added, removed = removed }
end

describe('harness.walkthrough_overview:', function()
  local a = hunk('h1', 'a.lua', 2, 3, 2, 1)
  local b = hunk('h2', 'b.lua', 1, 1, 1, 0)
  local c = hunk('h3', 'b.lua', 9, 9, 1, 1)
  local scope = {
    base = '1111111aaaa',
    head = '2222222bbbb',
    commits = { {} },
    files = {
      { path = 'a.lua', absolute = '/r/a.lua', hunks = { a } },
      { path = 'b.lua', absolute = '/r/b.lua', hunks = { b, c } },
    },
  }

  local function step(title, list, supporting)
    local ranges = vim.tbl_map(function(range)
      return { path = range[1], line = range[2], end_line = range[3] }
    end, list)

    return { title = title, path = ranges[1].path, line = ranges[1].line, ranges = ranges, supporting = supporting }
  end

  it('opens with the title, the size of the change, the summary and a table of steps with their files', function()
    local view = walkthrough_overview.render({
      title = 'Token refresh',
      summary = 'Refresh before expiry.',
      scope = scope,
      steps = {
        vim.tbl_extend('force', step('Core | refresh', { { '/r/a.lua', 2, 3 }, { '/r/b.lua', 1, 1 } }), {
          understood = true,
        }),
        step('Tests', { { '/r/b.lua', 9, 9 } }, true),
      },
      uncovered = {},
    }, { index = 2, seen = { true, true } })

    eq({
      '# Token refresh',
      '`1111111..2222222` · 1 commit · 2 files · 3 hunks · +4 -2',
      '1 of 2 understood',
      '',
      'Refresh before expiry.',
      '',
      '|   | Step | Files | Change |',
      '|---|---|---|---|',
      '| ✓ | 1. Core \\| refresh | a.lua, b.lua | +3 -1 |',
      '| ▸ | 2. Tests · supporting | b.lua | +1 -1 |',
    }, view.lines)
    eq({ [9] = { index = 1 }, [10] = { index = 2 } }, view.targets)
    eq(9, walkthrough_overview.first_target(view))
  end)

  it('marks a step seen but not yet understood apart from one understood', function()
    local view = walkthrough_overview.render({
      title = 'Walk',
      steps = { { path = '/w/a.lua', line = 1 }, { path = '/w/b.lua', line = 1 } },
    }, { index = 2, seen = { true } })

    assert.truthy(view.lines[#view.lines - 1]:find('^| · | 1%.'))
    assert.truthy(view.lines[#view.lines]:find('^| ▸ | 2%.'))
  end)

  it('lists the findings, counted by kind, each opening its lines', function()
    local issue =
      { kind = 'issue', path = '/r/a.lua', line = 4, end_line = 4, message = 'Nil when empty.', fix = { 'x' } }
    local nit = { kind = 'nitpick', path = '/r/b.lua', line = 9, end_line = 9, message = 'Typo.' }
    local core = step('Core', { { '/r/a.lua', 2, 3 } })

    core.findings = { issue, nit }

    local view = walkthrough_overview.render({ title = 'Review', steps = { core } })
    local at = vim.fn.index(view.lines, '## Findings · 1 issue, 1 nitpick') + 1

    assert.is_true(at > 0)
    eq('- ⚠ issue · a.lua:4 · fix · Nil when empty.', view.lines[at + 1])
    eq('- · nitpick · b.lua:9 · Typo.', view.lines[at + 2])
    eq({ finding = issue }, view.targets[at + 1])
  end)

  it('lists your comments, each opening its lines, and how to send them', function()
    local comment = { path = '/r/a.lua', line = 7, end_line = 7, text = 'Rename this.\nIt is unclear.' }
    local view = walkthrough_overview.render({
      title = 'Review',
      steps = { step('Core', { { '/r/a.lua', 2, 3 } }) },
      comments = { comment },
    })
    local at = vim.fn.index(view.lines, '## Your comments · 1') + 1

    eq('- ✎ a.lua:7 · Rename this.', view.lines[at + 1])
    eq({ comment = comment }, view.targets[at + 1])
    assert.truthy(view.lines[at + 2]:find('HarnessWalkthrough submit', 1, true))
  end)

  it('lists the hunks no step covers one row a file, opening the first of them', function()
    local view = walkthrough_overview.render({
      title = 'Review',
      scope = scope,
      steps = { step('Core', { { '/r/a.lua', 2, 3 } }) },
      uncovered = { b, c },
    })

    eq(
      { '## Not covered · 2 in 1 file', '- ○ b.lua · 2 hunks · h2-h3' },
      vim.list_slice(view.lines, #view.lines - 1)
    )
    eq({ hunk = b }, view.targets[#view.lines])
  end)

  it('leaves out the change column when the walkthrough is not a review, and shows the keys', function()
    local view = walkthrough_overview.render({
      title = 'How login works',
      steps = { { path = '/w/login.lua', line = 1 } },
    }, { keys = { open = '<CR>', next = ']]', stop = '<C-q>' } })

    eq('0 of 1 understood', view.lines[2])
    eq('|   | Step | Files |', view.lines[4])
    eq('|   | 1. login.lua | login.lua |', view.lines[6])
    eq('`<CR>` open · `]]` start · `<C-q>` end', view.lines[#view.lines])
  end)
end)

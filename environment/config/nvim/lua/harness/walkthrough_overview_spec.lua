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

  it('lists the hunks no step covers, each opening the hunk', function()
    local view = walkthrough_overview.render({
      title = 'Review',
      scope = scope,
      steps = { step('Core', { { '/r/a.lua', 2, 3 } }) },
      uncovered = { b, c },
    })

    eq({ '## Not covered', '- ○ h2 b.lua:1-1', '- ○ h3 b.lua:9-9' }, vim.list_slice(view.lines, #view.lines - 2))
    eq({ hunk = c }, view.targets[#view.lines])
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

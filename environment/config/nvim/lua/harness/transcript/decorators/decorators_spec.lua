local Block = require('harness.transcript.Block')
local decorators = require('harness.transcript.decorators')
local theme = require('harness.transcript.theme')

local eq = assert.are.same

local function make(kind, lines, fields)
  local block = Block.make(kind, lines, fields)

  block.start = fields and fields.start or 0
  block.finish = block.start + #lines + 1

  return block
end

local function find(marks, predicate)
  for _, mark in ipairs(marks) do
    if predicate(mark.opts, mark) then return mark end
  end
end

local function virt(opts)
  return opts.virt_text and table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, opts.virt_text))
end

describe('harness.transcript.decorators:', function()
  local function first_chunk(opts)
    return opts.virt_text and opts.virt_text[1][1]
  end

  it('marks a prompt\'s first row with the prompt icon and makes its text bold', function()
    local marks = decorators.decorate(make(Block.KIND.prompt, { '> a', '> b' }), {})

    eq({ theme.PROMPT_ICON, ' ' }, {
      find(marks, function(opts, mark)
        return mark.row == 0 and opts.virt_text_pos == 'overlay'
      end).opts.virt_text[1][1],
      find(marks, function(opts, mark)
        return mark.row == 1 and opts.virt_text_pos == 'overlay'
      end).opts.virt_text[1][1],
    })
    eq(2, #vim.tbl_filter(function(mark)
      return mark.opts.hl_group == 'UiPromptText'
    end, marks))
  end)

  it('says a prompt steered the turn', function()
    local marks = decorators.decorate(make(Block.KIND.prompt, { '> a' }, { steered = true }), {})

    assert.truthy(find(marks, function(opts)
      return virt(opts) == '  steered'
    end))
  end)

  it('shows a tool as its status icon and lowercase verb, its result aligned right when it fits', function()
    local block = make(Block.KIND.tool, { '-> Read a.lua' }, {
      name = 'Read',
      argument = 'a.lua',
      status = Block.STATUS.completed,
      category = Block.CATEGORY.read,
      output = 'a\nb\n',
    })
    local wide = decorators.decorate(block, { running = false, width = 80 })

    eq(theme.TOOL_ICONS[Block.STATUS.completed][1] .. 'read    ', virt(wide[2].opts))
    eq({ 0, 8 }, { wide[1].col, wide[1].opts.end_col })
    assert.truthy(find(wide, function(opts)
      return opts.virt_text_pos == 'right_align' and virt(opts) == '2 lines'
    end))
    assert.truthy(find(decorators.decorate(block, { running = false, width = 15 }), function(opts)
      return opts.virt_text_pos == 'eol' and virt(opts) == '  2 lines'
    end))

    block.first_child = true
    assert.truthy(find(decorators.decorate(block, { running = false, width = 80 }), function(opts)
      return opts.virt_text_pos == 'eol' and virt(opts) == '  2 lines'
    end))
  end)

  it('shows a live tool as running and times it, or says it waits for you', function()
    local block = make(
      Block.KIND.tool,
      { '-> Bash' },
      { id = 't', name = 'Bash', status = Block.STATUS.pending, started = 0 }
    )
    local ctx = { running = true, frame = 3, now = 3000 }
    local marks = decorators.decorate(block, ctx)

    assert.truthy(find(marks, function(opts)
      return first_chunk(opts) == theme.TOOL_ICONS.in_progress[1]
    end))
    assert.truthy(find(marks, function(opts)
      return opts.virt_text_pos == 'eol' and virt(opts) == '  3s'
    end))

    ctx.waiting = { { id = 't' } }
    assert.truthy(find(decorators.decorate(block, ctx), function(opts)
      return virt(opts) == '  waiting for you'
    end))
  end)

  it('draws a vgit patch: file line numbers, line backgrounds and changed words', function()
    local function block(whole)
      return make(Block.KIND.diff, { '```edit', '--- a.lua', 'x = 1', 'x = 2', '@@ -9 +9 @@', 'y', '```' }, {
        path = 'a.lua',
        whole = whole,
        patch = {
          rows = {
            { kind = 'remove', old_lnum = 4, number = { text = '  4 ', hl = 'GitSignsDelete' } },
            { kind = 'add', new_lnum = 4, number = { text = '  4 ', hl = 'GitSignsAdd' } },
            { kind = 'hunk' },
            { kind = 'context', old_lnum = 9, new_lnum = 9, number = { text = '  9 ', hl = 'GitLineNr' } },
          },
          highlights = {
            { row = 0, hl_group = 'GitSignsDeleteLn', line = true },
            { row = 1, hl_group = 'GitSignsAddLn', line = true },
            { row = 2, col_start = 0, col_end = 2, hl_group = 'GitPatchHeaderMarker' },
            { row = 3, hl_group = 'GitPatchContext', line = true },
          },
          words = { { row = 1, col = 4, texts = { { '2', 'GitWordAdd' } } } },
          syntax = function()
            return { { row = 3, col_start = 0, col_end = 1, hl_group = '@variable' } }
          end,
        },
      })
    end

    local marks = decorators.decorate(block(true), {})

    local function at(row, predicate)
      return find(marks, function(opts, mark)
        return mark.row == row and predicate(opts)
      end)
    end

    assert.truthy(at(2, function(opts)
      return virt(opts) == '  4 ' and opts.hl_mode == 'combine' and opts.virt_text[1][2] == 'UiDiffDeleteNumber'
    end))
    assert.truthy(at(2, function(opts)
      return opts.line_hl_group == 'GitSignsDeleteLn'
    end))
    assert.truthy(at(3, function(opts)
      return opts.virt_text_pos == 'overlay'
        and opts.hl_mode == 'combine'
        and virt(opts) == '2'
        and opts.virt_text[1][2] == 'GitWordAdd'
    end))
    assert.truthy(at(4, function(opts)
      return virt(opts) == theme.HUNK
    end))
    assert.truthy(at(5, function(opts)
      return opts.hl_group == '@variable' and opts.end_col == 1 and opts.priority == theme.SYNTAX_PRIORITY
    end))
    eq(false, at(4, function(opts)
      return opts.hl_group == 'GitPatchHeaderMarker'
    end) ~= nil)
    eq(false, at(5, function(opts)
      return opts.line_hl_group ~= nil
    end) ~= nil)
    assert.truthy(find(decorators.decorate(block(false), {}), function(opts, mark)
      return mark.row == 2 and virt(opts) == '    '
    end))
  end)

  it('borders an artifact with a rule above it, below it too when asked, keeping a nested rail', function()
    local settings = require('harness.settings.theme')
    local saved = settings:get('artifact_border')
    local fields = { start = 4, frame_top = true, frame_bottom = true, depth = 1, name = 'Bash' }
    local lines = { '-> Bash ls', '```output', 'a', '```' }

    local function borders()
      local out = {}

      for _, mark in ipairs(decorators.decorate(make(Block.KIND.tool, lines, fields), {})) do
        local line = mark.opts.virt_lines and mark.opts.virt_lines[1]

        if line then out[#out + 1] = { mark.row, mark.opts.virt_lines_above == true, line[1][1], line[2][2] } end
      end

      return out
    end

    settings:assign({ artifact_border = 'top' })
    local top = borders()
    settings:assign({ artifact_border = 'both' })
    local both = borders()
    settings:assign({ artifact_border = 'none' })
    local none = borders()
    settings:assign({ artifact_border = saved })

    eq({ { 4, true, theme.GUTTER, 'UiArtifactBorder' } }, top)
    eq({ { 4, true, theme.GUTTER, 'UiArtifactBorder' }, { 8, true, theme.GUTTER, 'UiArtifactBorder' } }, both)
    eq({}, none)
  end)

  it('draws a split patch: two columns, a hunk rule and per-side colours', function()
    local block = make(
      Block.KIND.diff,
      { '```edit', '--- a.lua', ' 1 x  │  1 x', ' 2 y  │  2 Y', '', ' 9 z  │  9 z', '```' },
      {
        path = 'a.lua',
        whole = true,
        patch = {
          layout = 'split',
          rows = {
            { kind = 'context', old_lnum = 1, new_lnum = 1, old_code = 5, new_code = 15 },
            { kind = 'remove', old_lnum = 2, new_lnum = 2, old_code = 5, new_code = 15 },
            { kind = 'hunk' },
            { kind = 'context', old_lnum = 9, new_lnum = 9, old_code = 5, new_code = 15 },
          },
          highlights = {
            { row = 1, col_start = 0, col_end = 4, hl_group = 'GitSignsDeleteLn' },
            { row = 1, col_start = 13, col_end = 16, hl_group = 'GitSignsAddLn' },
          },
          words = { { row = 1, col = 5, texts = { { 'y', 'GitWordDelete' } } } },
          voids = { { row = 1, col = 0, text = '⣿⣿' } },
          syntax = function()
            return {}
          end,
        },
      }
    )

    local marks = decorators.decorate(block, {})

    local function at(row, predicate)
      return find(marks, function(opts, mark)
        return mark.row == row and predicate(opts)
      end)
    end

    assert.truthy(at(3, function(opts)
      return opts.hl_group == 'GitSignsDeleteLn' and opts.end_col == 4 and opts.priority > theme.SYNTAX_PRIORITY
    end))
    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 3 and mark.col == 13 and opts.hl_group == 'GitSignsAddLn' and opts.end_col == 16
    end))
    assert.truthy(at(4, function(opts)
      return virt(opts) == theme.HUNK
    end))
    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 3 and mark.col == 5 and opts.virt_text_pos == 'overlay' and virt(opts) == 'y'
    end))
    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 3 and mark.col == 0 and opts.virt_text_pos == 'overlay' and virt(opts) == '⣿⣿'
    end))
    assert.truthy(at(0, function(opts)
      return opts.line_hl_group == 'UiMarkdownCode'
    end))
    assert.truthy(at(1, function(opts)
      return opts.line_hl_group == 'UiMarkdownCode'
    end))
    assert.truthy(at(6, function(opts)
      return opts.line_hl_group == 'UiMarkdownCode'
    end))
  end)

  it('ends a turn with a rule that carries its duration and tool count, and names any other reason', function()
    local function label(fields)
      local marks = decorators.decorate(make(Block.KIND.stop, { '*x*' }, fields), {})

      return virt(find(marks, function(opts)
        return opts.virt_text_pos == 'right_align'
      end).opts)
    end

    eq(' 4s · 2 tools ──', label({ reason = 'end_turn', duration = 4000, tools = 2 }))
    eq(' interrupted · 4s ──', label({ reason = 'cancelled', duration = 4000 }))
    eq(' done ──', label({ reason = 'end_turn' }))
  end)

  it('animates a live thought and times a finished one', function()
    local live = decorators.decorate(make(Block.KIND.thought, { 'x' }, { live = true }), { running = true, now = 0 })
    local done = decorators.decorate(make(Block.KIND.thought, { 'x' }, { started = 0, finished = 2000 }), {})

    eq('  ' .. theme.motion('thinking', 0), virt(live[1].opts))
    eq('  2s', virt(done[1].opts))
  end)

  it('draws every note as a cross, its label and its detail, with errors in the error colour', function()
    local error =
      decorators.decorate(make(Block.KIND.note, { 'error: not logged in', 'retry' }, { label = 'error' }), {})
    local refused = decorators.decorate(make(Block.KIND.note, { 'refused: Bash' }, { label = 'refused' }), {})

    eq(theme.TOOL_ICONS.failed[1], virt(error[1].opts))
    eq({ 0, 6, 'UiError' }, { error[2].col, error[2].opts.end_col, error[2].opts.hl_group })
    eq('UiError', error[3].opts.hl_group)
    eq('UiError', error[5].opts.hl_group)
    eq('UiMuted', refused[3].opts.hl_group)
    eq(0, #decorators.decorate(make(Block.KIND.note, { 'a' }), {}))
  end)

  it('draws plan entries with the plan marks, muting what is done', function()
    local marks = decorators.decorate(
      make(Block.KIND.plan, { 'plan', '- [x] read', '- [ ] edit' }, { statuses = { 'completed', 'in_progress' } }),
      {}
    )

    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 1 and virt(opts) == theme.PLAN_ICONS.completed[1]
    end))
    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 2 and virt(opts) == theme.PLAN_ICONS.in_progress[1]
    end))
    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 2 and opts.conceal == '' and opts.end_col == 6
    end))
  end)

  it('marks a tool its turn left unfinished, and one whose permission was refused or cancelled', function()
    local function tail(fields, ctx)
      local marks = decorators.decorate(
        make(Block.KIND.tool, { '-> Bash ls' }, vim.tbl_extend('force', { name = 'Bash', argument = 'ls' }, fields)),
        ctx or { running = false }
      )
      local found = find(marks, function(opts)
        return opts.virt_text_pos == 'eol'
      end)

      return found and virt(found.opts), marks
    end

    local text, marks = tail({ status = 'in_progress', interrupted = true })

    eq('  interrupted', text)
    eq(theme.TOOL_ICONS.failed[1], marks[2].opts.virt_text[1][1])
    eq('  refused', tail({ status = 'failed', denied = 'refused' }))
    eq('  cancelled', tail({ status = 'failed', denied = 'cancelled' }))
  end)

  it('rails nested blocks, branching at tools and closing the tree after the last child', function()
    local message = decorators.decorate(make(Block.KIND.message, { 'a' }, { depth = 1 }), {})
    local tool = decorators.decorate(make(Block.KIND.tool, { '-> Read' }, { name = 'Read', depth = 1 }), {})
    local last =
      decorators.decorate(make(Block.KIND.message, { '  a' }, { depth = 1, indented = true, last_child = true }), {})

    eq(2, #vim.tbl_filter(function(mark)
      return virt(mark.opts) == theme.GUTTER
    end, message))
    assert.truthy(find(tool, function(opts, mark)
      return mark.row == 0 and virt(opts) == theme.BRANCH
    end))
    assert.truthy(find(last, function(opts, mark)
      return mark.row == 0 and virt(opts) == theme.GUTTER and opts.virt_text_repeat_linebreak
    end))
    assert.truthy(find(last, function(opts, mark)
      return mark.row == 1 and virt(opts) == theme.BRANCH_END
    end))
  end)

  it('hides the blank row after a tool packed tight against the next, unless it closes a tree', function()
    local function hidden(fields)
      return find(decorators.decorate(make(Block.KIND.tool, { '-> Read' }, fields), {}), function(opts, mark)
        return mark.row == 1 and opts.conceal_lines == ''
      end) ~= nil
    end

    local base = { name = 'Read', status = Block.STATUS.completed }

    eq({ true, false, false }, {
      hidden(vim.tbl_extend('force', base, { tight = true })),
      hidden(base),
      hidden(vim.tbl_extend('force', base, { tight = true, depth = 1, last_child = true })),
    })
  end)

  it('shows a collapsed block muted behind an icon, with the key to open it accented', function()
    local block = make(Block.KIND.collapsed, { '3 earlier turns · <CR> to show' })
    local marks = decorators.decorate(block, {})

    eq(theme.COLLAPSED_ICON, virt(marks[1].opts))
    eq('UiMuted', marks[2].opts.hl_group)
    eq({ 19, 23, 'UiAccent' }, { marks[3].col, marks[3].opts.end_col, marks[3].opts.hl_group })
  end)

  it('sums up a finished sub-agent by time and tools, and counts tools while it runs', function()
    local function tail(fields, ctx)
      local marks = decorators.decorate(make(Block.KIND.tool, { '-> Task' }, fields), ctx or {})
      local found = find(marks, function(opts)
        return opts.virt_text_pos == 'eol'
      end)

      return found and virt(found.opts)
    end

    local base = { name = 'Task', nested = 3, started = 0, finished = 4000 }

    eq('  4s · 3 tools', tail(vim.tbl_extend('force', base, { status = Block.STATUS.completed })))
    eq('  4s · 3 tools', tail(vim.tbl_extend('force', base, { status = Block.STATUS.failed })))
    assert.truthy(tail(vim.tbl_extend('force', base, { status = Block.STATUS.in_progress, finished = nil }), {
      running = true,
      now = 2000,
    }):find('^  3 tools', 1))
  end)

  it('shows a delegating tool as running while its sub-agent runs, even after the call returned', function()
    local block = make(
      Block.KIND.tool,
      { '-> Agent' },
      { id = 'A', name = 'Agent', status = Block.STATUS.completed, nested = 2 }
    )
    local marks = decorators.decorate(block, { running = false, frame = 2, active = { A = true } })

    assert.truthy(find(marks, function(opts)
      return first_chunk(opts) == theme.TOOL_ICONS.in_progress[1]
    end))
    assert.truthy(find(marks, function(opts)
      return opts.virt_text_pos == 'eol' and virt(opts) == '  2 tools'
    end))
  end)

  describe('command output', function()
    local function output(lines, fields)
      local all = { '-> Bash make', '```output' }

      vim.list_extend(all, lines)
      all[#all + 1] = '```'

      return make(
        Block.KIND.tool,
        all,
        vim.tbl_extend('force', {
          name = 'Bash',
          argument = 'make',
          category = 'execute',
          status = Block.STATUS.completed,
        }, fields or {})
      )
    end

    local function highlights(marks)
      local out = {}

      for _, mark in ipairs(marks) do
        if mark.opts.hl_group and mark.opts.end_col then
          out[#out + 1] = { mark.row, mark.col, mark.opts.end_col, mark.opts.hl_group }
        end
      end

      return out
    end

    it('colours plain output the way a terminal would', function()
      local marks = decorators.decorate(output({ 'error: boom', 'fine' }), {})

      eq({ { 2, 0, 11, 'UiError' } }, highlights(marks))
    end)

    it('uses the colours the command printed instead, when it printed some', function()
      local marks = decorators.decorate(output({ 'error: boom', 'ok' }, { ansi = { { 2, 0, 2, 'UiAnsi2' } } }), {})

      eq({ { 3, 0, 2, 'UiAnsi2' } }, highlights(marks))
    end)

    it('leaves output in a known language to its syntax', function()
      local marks = decorators.decorate(output({ 'error: in json' }, { lang = 'json' }), {})

      eq({}, highlights(marks))
    end)

    it('sits the command on the terminal surface too, so the operation reads as one panel', function()
      local marks = decorators.decorate(output({ 'ok' }), {})

      assert.truthy(find(marks, function(opts, mark)
        return mark.row == 0 and opts.line_hl_group == 'UiTerminal'
      end))
    end)

    it('leaves other operations off the terminal surface', function()
      local read = make(
        Block.KIND.tool,
        { '-> Read a.lua', '```output', 'x', '```' },
        { name = 'Read', category = 'read', status = Block.STATUS.completed }
      )

      assert.is_nil(find(decorators.decorate(read, {}), function(opts)
        return opts.line_hl_group == 'UiTerminal'
      end))
    end)
  end)
end)

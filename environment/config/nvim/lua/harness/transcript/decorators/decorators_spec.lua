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

  it('spins a live tool and times it, or says it waits for you', function()
    local block = make(
      Block.KIND.tool,
      { '-> Bash' },
      { id = 't', name = 'Bash', status = Block.STATUS.pending, started = 0 }
    )
    local ctx = { running = true, frame = 3, now = 3000 }
    local marks = decorators.decorate(block, ctx)

    assert.truthy(find(marks, function(opts)
      return first_chunk(opts) == theme.SPINNER[3] .. ' '
    end))
    assert.truthy(find(marks, function(opts)
      return opts.virt_text_pos == 'eol' and virt(opts) == '  3s'
    end))

    ctx.waiting = { { id = 't' } }
    assert.truthy(find(decorators.decorate(block, ctx), function(opts)
      return virt(opts) == '  waiting for you'
    end))
  end)

  it('numbers diff lines by the injected file offset, hides the first hunk header and rails the rest', function()
    local block = make(Block.KIND.diff, { '```diff', '+++ a.txt', '@@ -1 +1 @@', '+x', '```' }, { path = 'a.txt' })
    local marks = decorators.decorate(block, {
      diff_offset = function()
        return 9
      end,
    })

    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 3 and virt(opts) == '  10 ' and opts.line_hl_group == 'UiDiffAdd'
    end))
    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 2 and opts.conceal_lines == ''
    end))
    assert.truthy(find(marks, function(opts, mark)
      return mark.row == 3 and virt(opts) == theme.GUTTER
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

  it('spins a live thought and times a finished one', function()
    local live = decorators.decorate(make(Block.KIND.thought, { 'x' }, { live = true }), { running = true, frame = 1 })
    local done = decorators.decorate(make(Block.KIND.thought, { 'x' }, { started = 0, finished = 2000 }), {})

    eq('  ' .. theme.SPINNER[1] .. ' thinking', virt(live[1].opts))
    eq('  2s', virt(done[1].opts))
  end)

  it('marks error notes and leaves others plain', function()
    eq(2, #decorators.decorate(make(Block.KIND.note, { 'a', 'b' }, { error = true }), {}))
    eq(0, #decorators.decorate(make(Block.KIND.note, { 'a' }), {}))
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
    local block = make(Block.KIND.collapsed, { '3 earlier turns · <CR> to show' }, { hidden = 3 })
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

  it('spins a delegating tool while its sub-agent runs, even after the call returned and the turn ended', function()
    local block = make(
      Block.KIND.tool,
      { '-> Agent' },
      { id = 'A', name = 'Agent', status = Block.STATUS.completed, nested = 2 }
    )
    local marks = decorators.decorate(block, { running = false, frame = 2, active = { A = true } })

    assert.truthy(find(marks, function(opts)
      return first_chunk(opts) == theme.SPINNER[2] .. ' '
    end))
    assert.truthy(find(marks, function(opts)
      return opts.virt_text_pos == 'eol' and virt(opts) == '  2 tools'
    end))
  end)
end)

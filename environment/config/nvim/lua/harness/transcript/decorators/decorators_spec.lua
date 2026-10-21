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
  it('gives a prompt a header and a bar on each of its rows, with a separator after the first turn', function()
    local first = decorators.decorate(make(Block.KIND.prompt, { 'a', 'b' }, { first = true }), {})
    local later = decorators.decorate(make(Block.KIND.prompt, { 'a' }), {})

    eq(1, #first[1].opts.virt_lines)
    eq(2, #later[1].opts.virt_lines)
    eq(2, #vim.tbl_filter(function(mark)
      return mark.opts.line_hl_group == 'UiPrompt'
    end, first))
  end)

  it('shows a finished tool by its status icon and summarises a read without a body', function()
    local block = make(Block.KIND.tool, { '## Read a.lua' }, {
      name = 'Read',
      status = Block.STATUS.completed,
      category = Block.CATEGORY.read,
      output = 'a\nb\n',
    })
    local marks = decorators.decorate(block, { running = false })

    assert.truthy(find(marks, function(opts)
      return virt(opts) == theme.TOOL_ICONS[Block.STATUS.completed][1]
    end))
    assert.truthy(find(marks, function(opts)
      return opts.virt_lines and opts.virt_lines[1][2][1] == 'Read 2 lines'
    end))
  end)

  it('spins a live tool and times it, or says it waits for you', function()
    local block = make(
      Block.KIND.tool,
      { '## Bash' },
      { id = 't', name = 'Bash', status = Block.STATUS.pending, started = 0 }
    )
    local ctx = { running = true, frame = 3, now = 3000 }
    local marks = decorators.decorate(block, ctx)

    assert.truthy(find(marks, function(opts)
      return virt(opts) == theme.SPINNER[3] .. ' '
    end))
    assert.truthy(find(marks, function(opts)
      return opts.virt_text_pos == 'eol' and virt(opts) == '  3s'
    end))

    ctx.waiting = { { id = 't' } }
    assert.truthy(find(decorators.decorate(block, ctx), function(opts)
      return virt(opts) == '  waiting for you'
    end))
  end)

  it('numbers diff lines by the injected file offset and hides hunk headers', function()
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
      return mark.row == 2 and opts.conceal == ''
    end))
  end)

  it('labels a stop with its reason, duration and tool count', function()
    local marks = decorators.decorate(
      make(Block.KIND.stop, { 'end_turn' }, { reason = 'end_turn', duration = 4000, tools = 2 }),
      {}
    )

    assert.truthy(find(marks, function(opts)
      return virt(opts) and virt(opts):find('in 4s · 2 tools', 1, true)
    end))
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

  it('adds the gutter to nested blocks', function()
    local marks = decorators.decorate(make(Block.KIND.message, { 'a' }, { depth = 1 }), {})

    eq(2, #vim.tbl_filter(function(mark)
      return virt(mark.opts) == theme.GUTTER
    end, marks))
  end)

  it('heads the reply from the answered prompt\'s blank line, which nothing conceals', function()
    local marks = decorators.decorate(make(Block.KIND.prompt, { '> hi' }, { first = true, answered = true }), {
      agent = 'Claude',
    })
    local header = find(marks, function(opts)
      return opts.virt_lines and opts.virt_lines[1][1][1] == ' ' .. theme.AGENT_ICON .. 'Claude'
    end)

    eq(1, header.row)
    assert.is_falsy(header.opts.virt_lines_above)
  end)

  it('shows a collapsed block muted behind an icon, with the key to open it accented', function()
    local block = make(Block.KIND.collapsed, { '3 earlier turns · <CR> to show' }, { hidden = 3 })
    local marks = decorators.decorate(block, {})

    eq(theme.COLLAPSED_ICON, virt(marks[1].opts))
    eq('UiMuted', marks[2].opts.hl_group)
    eq({ 19, 23, 'UiAccent' }, { marks[3].col, marks[3].opts.end_col, marks[3].opts.hl_group })
  end)

  it('sums up a finished sub-agent by outcome, time and tools, and counts tools while it runs', function()
    local function tail(fields, ctx)
      local marks = decorators.decorate(make(Block.KIND.tool, { '-> Task' }, fields), ctx or {})
      local found = find(marks, function(opts)
        return opts.virt_text_pos == 'eol'
      end)

      return found and virt(found.opts)
    end

    local base = { name = 'Task', nested = 3, started = 0, finished = 4000 }

    eq('  done in 4s · 3 tools', tail(vim.tbl_extend('force', base, { status = Block.STATUS.completed })))
    eq('  failed in 4s · 3 tools', tail(vim.tbl_extend('force', base, { status = Block.STATUS.failed })))
    assert.truthy(tail(vim.tbl_extend('force', base, { status = Block.STATUS.in_progress, finished = nil }), {
      running = true,
      now = 2000,
    }):find('^  3 tools', 1))
  end)
end)

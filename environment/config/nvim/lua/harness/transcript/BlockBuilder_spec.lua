local EditPatches = require('harness.transcript.EditPatches')
local blocks = require('harness.transcript.BlockBuilder')
local events = require('harness.events')

local Block = blocks.Block

local eq = assert.are.same

local function kinds(list)
  return vim.tbl_map(function(block)
    return block.kind
  end, list)
end

describe('harness.transcript.BlockBuilder:', function()
  it('streams consecutive text into one block, even across events it does not show', function()
    local list = blocks.build({
      { kind = 'message', text = 'Look' },
      { kind = 'usage', used = 1, size = 2 },
      { kind = 'message', text = 'ing' },
    })

    eq({ Block.KIND.title, Block.KIND.message }, kinds(list))
    eq({ 'Looking' }, list[2].lines)
  end)

  it('shows thoughts as a callout', function()
    local list = blocks.build({ { kind = 'thought', text = 'first\n\nsecond' } })

    eq({ '> [!thought]', '> first', '>', '> second' }, list[2].lines)
  end)

  it('shows only the latest plan of a turn', function()
    local list = blocks.build({
      events.prompt('go'),
      { kind = 'plan', entries = { { content = 'a', status = Block.STATUS.pending } } },
      { kind = 'message', text = 'working' },
      { kind = 'plan', entries = { { content = 'a', status = Block.STATUS.completed } } },
      events.prompt('again'),
      { kind = 'plan', entries = { { content = 'b' } } },
    })

    eq({
      Block.KIND.title,
      Block.KIND.prompt,
      Block.KIND.message,
      Block.KIND.plan,
      Block.KIND.prompt,
      Block.KIND.plan,
    }, kinds(list))
    eq({ '**plan**', '- [x] a' }, list[4].lines)
  end)

  it('gives a tool block the latest title and status of its call', function()
    local list = blocks.build({
      { kind = 'tool_call', id = 't1', title = 'Read', status = Block.STATUS.pending, diffs = {} },
      { kind = 'tool_update', id = 't1', title = 'Read a.lua', status = Block.STATUS.completed, diffs = {} },
    })

    eq({ '-> Read a.lua' }, list[2].lines)
    eq('t1', list[2].id)
    eq(Block.STATUS.completed, list[2].status)
  end)

  it('closes a fence a finished message left open, so it cannot swallow the next block', function()
    local list = blocks.build({
      { kind = 'message', text = '```lua\nlocal x = 1' },
      events.stop('end_turn'),
    })

    eq({ '```lua', 'local x = 1', '```' }, list[2].lines)
  end)

  it('leaves the fence of a message that is still streaming alone', function()
    local list = blocks.build({ { kind = 'message', text = '```lua\nlocal x = 1' } })

    eq({ '```lua', 'local x = 1' }, list[2].lines)
  end)

  it('records where each block sits in the lines', function()
    local list = blocks.build({ events.prompt('hi'), { kind = 'message', text = 'a\nb' } })
    local lines = blocks.lines(list)

    eq({ '# Harness', '', '> hi', '', 'a', 'b' }, lines)
    eq({ 0, 2 }, { list[1].start, list[1].finish })
    eq({ 2, 4 }, { list[2].start, list[2].finish })
    eq({ 4, 6 }, { list[3].start, list[3].finish })
  end)

  it('labels a tool by its name and main argument', function()
    local list = blocks.build({
      {
        kind = 'tool_call',
        id = 't1',
        name = 'Bash',
        title = 'Terminal',
        input = { command = 'make test' },
        diffs = {},
      },
      { kind = 'tool_call', id = 't2', name = 'mcp__nvim__buffer_read', input = { path = '/repo/a.lua' }, diffs = {} },
    }, nil, { dir = '/repo' })

    eq({ '-> Bash make test' }, list[2].lines)
    eq({ 'Bash', 'make test' }, { list[2].name, list[2].argument })
    eq({ '-> nvim:buffer_read a.lua' }, list[3].lines)
  end)

  it('shows command output in a fence, folding all but the first lines', function()
    local output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, 10)), '\n')
    local list = blocks.build({
      { kind = 'tool_call', id = 't1', name = 'Bash', category = 'execute', input = { command = 'seq' }, diffs = {} },
      { kind = 'tool_update', id = 't1', status = Block.STATUS.completed, output = output, diffs = {} },
    })
    local tool = list[2]

    eq('```output', tool.lines[2])
    eq('10', tool.lines[12])
    eq('```', tool.lines[13])
    eq({ { 2 + require('harness.settings.transcript'):get('preview_lines'), 12 } }, tool.folds)
  end)

  it('leaves reads and agent transcripts without output', function()
    local history = {
      { kind = 'tool_call', id = 't1', name = 'Read', category = 'read', diffs = {} },
      { kind = 'tool_update', id = 't1', status = Block.STATUS.completed, output = 'file text', diffs = {} },
      { kind = 'tool_call', id = 't2', name = 'Bash', category = 'execute', diffs = {} },
      { kind = 'tool_update', id = 't2', status = Block.STATUS.completed, output = 'out', diffs = {} },
    }

    eq(1, #blocks.build(history)[2].lines)
    eq(4, #blocks.build(history)[3].lines)
    eq(1, #blocks.build(history, nil, { outputs = false })[3].lines)
  end)

  it('counts a tool\'s diff lines', function()
    local list = blocks.build({
      {
        kind = 'tool_call',
        id = 't1',
        name = 'Edit',
        diffs = { { path = '/a.lua', old = 'a\nb\n', new = 'a\nc\nd\n' } },
      },
    })

    eq({ 2, 1 }, { list[2].added, list[2].removed })
    eq(Block.KIND.diff, list[3].kind)
  end)

  it('times turns and thoughts, and marks the thought still streaming', function()
    local history = {
      events.prompt('go'),
      { kind = 'thought', text = 'hmm' },
      { kind = 'message', text = 'ok' },
      events.stop('end_turn'),
    }
    local times = { 1000, 2000, 6000, 9000 }
    local list = blocks.build(history, nil, { times = times })

    eq({ 2000, 6000 }, { list[3].started, list[3].finished })
    eq(8000, list[5].duration)
    eq('end_turn', list[5].reason)
    eq(true, blocks.build({ { kind = 'thought', text = 'hmm' } }, nil, { running = true })[2].live)
  end)

  it('marks the first prompt, packs runs of tools and diffs tight, and attaches a diff to its tool', function()
    local list = blocks.build({
      events.prompt('one'),
      { kind = 'tool_call', id = 't1', name = 'Read', diffs = {} },
      { kind = 'tool_call', id = 't2', name = 'Edit', diffs = { { path = 'a.txt', old = 'x', new = 'y' } } },
      { kind = 'message', text = 'done' },
      events.prompt('two'),
    })

    eq(
      { 'title', 'prompt', 'tool', 'tool', 'diff', 'message', 'prompt' },
      vim.tbl_map(function(block)
        return block.kind
      end, list)
    )
    eq({ true, false }, { list[2].first, list[7].first })
    eq({ true, true }, { list[3].tight, list[4].tight })
    assert.is_nil(list[5].tight)
    assert.is_nil(list[6].tight)
    eq(true, list[5].attached)
  end)

  it('closes each sub-agent on its last child and indents the sub-agent\'s prose', function()
    local list = blocks.build({
      events.prompt('go'),
      { kind = 'tool_call', id = 'A', name = 'Agent', diffs = {} },
      { kind = 'tool_call', id = 'r', name = 'Read', parent = 'A', diffs = {} },
      { kind = 'message', text = 'found it\n\nall done', parent = 'A' },
    })

    eq({ true, true }, { list[3].tight, list[4].tight })
    eq({ true, nil }, { list[4].first_child, list[4].last_child })
    eq({ nil, true }, { list[5].first_child, list[5].last_child })
    eq(true, list[5].indented)
    eq({ '  found it', '', '  all done' }, list[5].lines)
  end)

  it('labels tools from standard ACP fields, whatever agent sent them', function()
    local list = blocks.build({
      {
        kind = 'tool_call',
        id = 'a',
        title = 'Run ls -la',
        category = 'execute',
        input = { command = { 'ls', '-la' } },
        diffs = {},
      },
      {
        kind = 'tool_call',
        id = 'b',
        title = 'Reading',
        category = 'read',
        locations = { { path = '/repo/x.lua' } },
        diffs = {},
      },
      { kind = 'tool_call', id = 'c', title = 'Searching for foo in src', category = 'search', diffs = {} },
    }, nil, { dir = '/repo' })

    eq({ '-> Run ls -la' }, list[2].lines)
    eq({ '-> Reading x.lua' }, list[3].lines)
    eq({ '-> Searching for foo in src' }, list[4].lines)
  end)

  describe('diffs', function()
    local function diff(new)
      return { path = '/a.lua', old = 'local x = 1\n', new = new }
    end

    local function diff_blocks(list)
      return vim.tbl_filter(function(block)
        return block.kind == Block.KIND.diff
      end, list)
    end

    it('shows the latest diff a tool reported, right under the tool', function()
      local list = blocks.build({
        { kind = 'tool_call', id = 't1', name = 'Edit', diffs = { diff('local x = 2\n') } },
        { kind = 'message', text = 'thinking it over' },
        { kind = 'tool_update', id = 't1', diffs = { diff('local x = 3\n') } },
      })
      local shown = diff_blocks(list)

      eq(1, #shown)
      eq(Block.KIND.diff, list[3].kind)
      assert.is_truthy(vim.tbl_contains(shown[1].lines, 'local x = 3'))
      assert.is_falsy(vim.tbl_contains(shown[1].lines, 'local x = 2'))
      eq(
        { 'remove', 'add' },
        vim.tbl_map(function(row)
          return row.kind
        end, shown[1].patch.rows)
      )
    end)

    it('lays an edit out against the whole file when it can find it, with vgit\'s rows', function()
      local edits = EditPatches(function()
        return { 'local a = 0', 'local x = 3', 'return x' }
      end)
      local shown = diff_blocks(blocks.build({
        {
          kind = 'tool_call',
          id = 't1',
          name = 'Edit',
          status = Block.STATUS.completed,
          diffs = { diff('local x = 3\n') },
        },
      }, nil, { edits = edits }))[1]

      eq({ '```edit', '--- /a.lua', 'local a = 0', 'local x = 1', 'local x = 3', 'return x', '```' }, shown.lines)
      eq(true, shown.whole)
      eq({ 2, 2 }, { shown.patch.rows[2].old_lnum, shown.patch.rows[3].new_lnum })
      eq({
        filename = '/a.lua',
        old_lines = { 'local a = 0', 'local x = 1', 'return x' },
        new_lines = {
          'local a = 0',
          'local x = 3',
          'return x',
        },
      }, shown.edit)
    end)

    it('gives agents a classic +/- diff when building text', function()
      local shown = diff_blocks(blocks.build({
        { kind = 'tool_call', id = 't1', name = 'Edit', diffs = { diff('local x = 3\n') } },
      }, nil, { outputs = false }))[1]

      eq({ '```diff', '--- /a.lua', '@@ -1 +1 @@', '-local x = 1', '+local x = 3', '```' }, shown.lines)
      eq({ 1, 1 }, { shown.added, shown.removed })
    end)

    it('shows a diff that only arrives with a later update under the tool', function()
      local list = blocks.build({
        { kind = 'tool_call', id = 't1', name = 'Edit', diffs = {} },
        { kind = 'message', text = 'between' },
        { kind = 'tool_update', id = 't1', diffs = { diff('local x = 2\n') } },
      })

      eq({ Block.KIND.title, Block.KIND.tool, Block.KIND.diff, Block.KIND.message }, kinds(list))
      eq(1, list[2].added)
    end)

    it('keeps the attempted diff when a later update carries only text', function()
      local list = blocks.build({
        { kind = 'tool_call', id = 't1', name = 'Edit', diffs = { diff('local x = 2\n') } },
        { kind = 'tool_update', id = 't1', status = Block.STATUS.failed, output = 'refused', diffs = {} },
      })

      eq(1, #diff_blocks(list))
    end)

    it('shows every file of a multi-file edit', function()
      local list = blocks.build({
        {
          kind = 'tool_call',
          id = 't1',
          name = 'Edit',
          diffs = { diff('local x = 2\n'), { path = '/b.lua', old = '', new = 'y = 1\n' } },
        },
      })

      eq(2, #diff_blocks(list))
      eq({ 2, 1 }, { list[2].added, list[2].removed })
    end)
  end)

  describe('sub-agents', function()
    it('nests a sub-agent\'s work under the tool call that started it, counting its tools', function()
      local list = blocks.build({
        { kind = 'tool_call', id = 'task1', name = 'Task', input = { description = 'list files' }, diffs = {} },
        { kind = 'tool_call', id = 'inner', name = 'Bash', parent = 'task1', input = { command = 'ls' }, diffs = {} },
        { kind = 'message', text = 'two ', parent = 'task1' },
        { kind = 'message', text = 'files', parent = 'task1' },
        { kind = 'tool_update', id = 'task1', status = Block.STATUS.completed, diffs = {} },
        { kind = 'message', text = 'parent done' },
      })

      eq({ Block.KIND.title, Block.KIND.tool, Block.KIND.tool, Block.KIND.message, Block.KIND.message }, kinds(list))
      eq({ nil, 'task1', 'task1', nil }, { list[2].parent, list[3].parent, list[4].parent, list[5].parent })
      eq({ nil, 1, 1, nil }, { list[2].depth, list[3].depth, list[4].depth, list[5].depth })
      eq({ '  two files' }, list[4].lines)
      eq(1, list[2].nested)
    end)
  end)

  describe('steering and late tool updates', function()
    it('keeps a steered prompt in the turn it steered, timing the turn from its first prompt', function()
      local history = {
        events.prompt('run the long thing'),
        { kind = 'tool_call', id = 't1', name = 'Bash', status = Block.STATUS.pending, diffs = {} },
        events.prompt('skip it', { steered = true }),
        { kind = 'tool_update', id = 't1', status = Block.STATUS.completed, diffs = {} },
        { kind = 'message', text = 'skipped' },
        events.stop('end_turn'),
      }
      local list = blocks.build(history, nil, { times = { 0, 1000, 5000, 6000, 7000, 9000 } })

      eq({
        Block.KIND.title,
        Block.KIND.prompt,
        Block.KIND.tool,
        Block.KIND.prompt,
        Block.KIND.message,
        Block.KIND.stop,
      }, kinds(list))
      eq(true, list[4].steered)
      eq(Block.STATUS.completed, list[3].status)
      eq(9000, list[6].duration)
    end)

    it('rebuilds a finished turn whose tool completes during a later turn', function()
      local cache = {}
      local history = {
        events.prompt('start a background job'),
        { kind = 'tool_call', id = 'bg', name = 'Bash', status = Block.STATUS.in_progress, diffs = {} },
        events.stop('end_turn'),
        events.prompt('anything new?'),
      }

      eq(Block.STATUS.in_progress, blocks.build(history, nil, { cache = cache })[3].status)

      history[#history + 1] = { kind = 'tool_update', id = 'bg', status = Block.STATUS.completed, diffs = {} }

      eq(Block.STATUS.completed, blocks.build(history, nil, { cache = cache })[3].status)
    end)
  end)

  describe('fenced output', function()
    it('shows tool output verbatim inside a fence it cannot close', function()
      local list = blocks.build({
        { kind = 'tool_call', id = 't1', name = 'Bash', category = 'execute', diffs = {} },
        { kind = 'tool_update', id = 't1', status = 'completed', output = 'before\n```\nafter', diffs = {} },
      })

      eq({ '-> Bash', '````output', 'before', '```', 'after', '````' }, list[2].lines)
    end)

    it('closes a finished message\'s open fence with the same marker', function()
      local list = blocks.build({
        { kind = 'message', text = '````md\n```lua\nx\n```' },
        events.stop('end_turn'),
      })

      eq('````', list[2].lines[#list[2].lines])
    end)
  end)

  it('collapses turns older than live_turns into one block, building only the recent ones', function()
    local history = {}

    for i = 1, 5 do
      events.append(history, events.prompt('turn ' .. i))
      events.append(history, { kind = 'message', text = 'reply ' .. i })
    end

    local list = blocks.build(history, nil, { live_turns = 2 })

    eq(Block.KIND.collapsed, list[2].kind)
    eq(3, list[2].hidden)
    eq({ '3 earlier turns · <CR> to show' }, list[2].lines)
    eq('> turn 4', list[3].lines[1])
    eq(#blocks.build(history, nil, {}) - 6 + 1, #list)
  end)

  it('collapses nothing when the session is within live_turns', function()
    local history = {}

    events.append(history, events.prompt('only'))

    for _, block in ipairs(blocks.build(history, nil, { live_turns = 2 })) do
      assert.are_not.equal(Block.KIND.collapsed, block.kind)
    end
  end)

  describe('tool groups', function()
    local function tool(id, category, status)
      return {
        { kind = 'tool_call', id = id, name = id, category = category, diffs = {} },
        { kind = 'tool_update', id = id, status = status or Block.STATUS.completed, output = 'x', diffs = {} },
      }
    end

    local function history_of(...)
      local out = { events.prompt('look') }

      for _, events_of in ipairs({ ... }) do
        vim.list_extend(out, events_of)
      end

      return out
    end

    it('groups a run of finished reads and searches under one header, nesting the tools', function()
      local list = blocks.build(
        history_of(tool('a', 'read'), tool('b', 'read'), tool('c', 'search'), tool('d', 'execute')),
        nil,
        { groups = true }
      )

      eq({ 'title', 'prompt', 'tool', 'tool', 'tool', 'tool', 'tool' }, kinds(list))
      eq('Read 2 files, searched 1 pattern', list[3].name)
      eq(3, list[3].grouped)
      eq({ 1, list[3].id }, { list[4].depth, list[4].parent })
      eq({ nil, true }, { list[5].last_child, list[6].last_child })
      assert.is_nil(list[7].depth)
    end)

    it('leaves single tools, failed tools and other categories ungrouped', function()
      local list = blocks.build(
        history_of(tool('a', 'read'), tool('b', 'execute'), tool('c', 'read'), tool('d', 'read', Block.STATUS.failed)),
        nil,
        { groups = true }
      )

      for _, block in ipairs(list) do
        assert.is_nil(block.grouped)
      end
    end)

    it('waits for a run at the live end of a running turn to finish before grouping it', function()
      local history = history_of(tool('a', 'read'), tool('b', 'read'))

      assert.is_nil(blocks.build(history, nil, { groups = true, running = true })[3].grouped)
      eq(2, blocks.build(history, nil, { groups = true })[3].grouped)
    end)

    it('groups only when asked, so agents reading the session see every tool', function()
      for _, block in ipairs(blocks.build(history_of(tool('a', 'read'), tool('b', 'read')))) do
        assert.is_nil(block.grouped)
      end
    end)
  end)

  it('nests each parallel sub-agent\'s work under its own call, whatever order it arrives in', function()
    local function call(id, name, parent)
      return { kind = 'tool_call', id = id, name = name, category = 'other', parent = parent, diffs = {} }
    end

    local function done(id)
      return { kind = 'tool_update', id = id, status = Block.STATUS.completed, output = 'x', diffs = {} }
    end

    local history = {
      events.prompt('two agents'),
      call('A', 'Agent'),
      call('B', 'Agent'),
      done('A'),
      done('B'),
      call('a1', 'Read', 'A'),
      { kind = 'message', text = 'started both' },
      call('a2', 'Bash', 'A'),
      call('b1', 'Read', 'B'),
      call('b2', 'Bash', 'B'),
      { kind = 'message', text = 'report A', parent = 'A' },
      { kind = 'message', text = 'report B', parent = 'B' },
      events.stop('end_turn'),
    }

    local list = blocks.build(history)
    local order = vim.tbl_map(function(block)
      return block.name or block.lines[1]
    end, vim.list_slice(list, 3))

    eq(
      { 'Agent', 'Read', 'Bash', '  report A', 'Agent', 'Read', 'Bash', '  report B', 'started both', '*end_turn*' },
      order
    )
    eq(2, list[3].nested)
    eq(2, list[7].nested)
    eq({ 'A', 'A', 'A' }, { list[4].parent, list[5].parent, list[6].parent })
  end)

  it('finishes a delegating tool when its nested work last moved, not when the call returned', function()
    local history = {
      events.prompt('go'),
      { kind = 'tool_call', id = 'A', name = 'Agent', category = 'other', diffs = {} },
      { kind = 'tool_update', id = 'A', status = Block.STATUS.completed, diffs = {} },
      { kind = 'tool_call', id = 'a1', name = 'Bash', category = 'execute', parent = 'A', diffs = {} },
      { kind = 'tool_update', id = 'a1', status = Block.STATUS.completed, output = 'x', diffs = {} },
      { kind = 'message', text = 'report', parent = 'A' },
    }
    local times = { 0, 100, 1000, 2000, 9000, 11000 }
    local agent = blocks.build(history, nil, { times = times })[3]

    eq(100, agent.started)
    eq(11000, agent.finished)
  end)
end)

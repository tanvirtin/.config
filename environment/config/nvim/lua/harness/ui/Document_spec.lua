local Document = require('harness.ui.Document')
local EditLog = require('harness.edits.EditLog')
local buffers = require('core.buffers')
local theme = require('harness.transcript.theme')
local blocks = require('harness.transcript.BlockBuilder')
local events = require('harness.types.events')

local Block = blocks.Block

local eq = assert.are.same

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function marks(buf, ns)
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

describe('harness.ui.Document:', function()
  local buf, document, history

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_buf(0, buf)
    document = Document(buf)
    history = {}
  end)

  after_each(function()
    vim.cmd('enew!')
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  local function emit(event)
    events.append(history, event)
    document:write(blocks.build(history))
  end

  it('leaves a prompt as typed, with no markdown drawn over it', function()
    emit(events.prompt('see [x] and `code`'))

    local prompt = document.blocks[2]
    local drawn = vim.api.nvim_buf_get_extmarks(
      buf,
      require('ui.markdown.Renderer').NAMESPACE,
      { prompt.start, 0 },
      { prompt.finish - 1, -1 },
      {}
    )

    eq({}, drawn)
  end)

  it('colours a command once its syntax is loaded, without holding up the first draw', function()
    local saved = Document.COMMAND_LANG[Block.CATEGORY.execute]

    Document.COMMAND_LANG[Block.CATEGORY.execute] = 'lua'
    emit({
      kind = 'tool_call',
      id = 't',
      name = 'Bash',
      category = 'execute',
      input = { command = 'local x = 1' },
      diffs = {},
    })

    local tool = document.blocks[#document.blocks]

    local function keywords()
      local found = 0

      for _, mark in ipairs(marks(buf, Document.NAMESPACE)) do
        if mark[2] == tool.start and mark[4].hl_group == '@keyword.lua' then found = found + 1 end
      end

      return found
    end

    vim.wait(200, function()
      return keywords() > 0
    end)
    Document.COMMAND_LANG[Block.CATEGORY.execute] = saved
    eq(1, keywords())
  end)

  it('writes the transcript and leaves the buffer read-only and unmodified', function()
    emit(events.prompt('hi'))

    eq({ '# untitled', '', '> hi', '' }, lines(buf))
    eq(false, vim.bo[buf].modifiable)
    eq(false, vim.bo[buf].modified)
  end)

  it('only rewrites from the first line that changed', function()
    emit(events.prompt('hi'))
    emit({ kind = 'message', text = 'one\ntw' })

    local written = {}

    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first, last_old, last_new)
        written[#written + 1] = { first, last_old, last_new }
      end,
    })

    emit({ kind = 'message', text = 'o' })

    eq({ '# untitled', '', '> hi', '', 'one', 'two' }, lines(buf))
    eq({ { 5, 6, 6 } }, written)
  end)

  it('rewrites only the lines that changed when a long tail changes at both ends', function()
    local limit = Document.SPLICE_LINES

    Document.SPLICE_LINES = 0

    for i = 1, 5 do
      emit(events.prompt('ask ' .. i))
      emit({ kind = 'message', text = 'reply ' .. i })
      emit(events.stop('end_turn'))
    end

    local written = {}

    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first, last_old, last_new)
        written[#written + 1] = { first, last_old, last_new }
      end,
    })

    history[2].text = 'reply one'
    emit(events.prompt('ask 6'))
    Document.SPLICE_LINES = limit

    local expected = blocks.lines(blocks.build(history))

    eq(lines(buf)[#lines(buf)], '')
    eq(vim.list_slice(lines(buf), 1, #lines(buf) - 1), vim.list_slice(expected, 1, #lines(buf) - 1))
    eq(2, #written)
    eq({ 4, 5, 5 }, written[2])
  end)

  it('lays out edits as one replacement when short, and as hunks from the bottom up when long', function()
    local old, new = { 'a', 'b', 'c', 'd' }, { 'a', 'B', 'c', 'd', 'e' }

    eq({ { lines = new, from = 3, to = 7 } }, Document.edits(old, new, 3))

    local limit = Document.SPLICE_LINES

    Document.SPLICE_LINES = 0

    local edits = Document.edits(old, new, 3)

    Document.SPLICE_LINES = limit

    eq({ { lines = { 'e' }, from = 7, to = 7 }, { lines = { 'B' }, from = 4, to = 5 } }, edits)
  end)

  it('does not touch the buffer when nothing changed', function()
    emit(events.prompt('hi'))

    local tick = vim.api.nvim_buf_get_changedtick(buf)

    document:write(blocks.build(history))

    eq(tick, vim.api.nvim_buf_get_changedtick(buf))
  end)

  it('shows a tool call\'s status as an extmark, and updates it without rewriting the text', function()
    emit({ kind = 'tool_call', id = 't1', title = 'Read a.lua', status = Block.STATUS.pending, diffs = {} })

    local icon = function()
      for _, mark in ipairs(marks(buf, Document.NAMESPACE)) do
        if mark[4].virt_text then return mark[4].virt_text[1][1] end
      end
    end

    eq(theme.TOOL_ICONS[Block.STATUS.pending][1], icon())

    local tick = vim.api.nvim_buf_get_changedtick(buf)

    emit({ kind = 'tool_update', id = 't1', status = Block.STATUS.completed, diffs = {} })

    eq(tick, vim.api.nvim_buf_get_changedtick(buf))
    eq(theme.TOOL_ICONS[Block.STATUS.completed][1], icon())
  end)

  describe('a streaming reply', function()
    local Renderer = require('ui.markdown.Renderer')

    local function drawn(bufnr)
      local out = {}

      for _, mark in ipairs(marks(bufnr, Renderer.NAMESPACE)) do
        out[#out + 1] = vim.inspect({ mark[2], mark[3], mark[4] })
      end

      table.sort(out)

      return out
    end

    local function stream(text, size)
      for i = 1, #text, size do
        emit({ kind = 'message', text = text:sub(i, i + size - 1) })
      end
    end

    it('redraws only the block still being written', function()
      local annotated = {}
      local annotate = document.renderer.annotate

      document.renderer.annotate = function(renderer, rows, offset, from)
        annotated[#annotated + 1] = #rows
        return annotate(renderer, rows, offset, from)
      end

      emit(events.prompt('hi'))
      stream('para one\n\npara two\n\npara th', 100)
      emit({ kind = 'message', text = 'ree' })

      eq(1, annotated[#annotated])
      eq('para three', lines(buf)[#lines(buf)])
    end)

    it('draws a live thought, growing inside its callout, the same as one written in one go', function()
      local text =
        'First thought with `code`.\n\n- a list\n- of points\n\n```lua\nlocal a = 1\n\nreturn a\n```\n\nLast thought.'
      local running = { running = true }
      local annotated = {}
      local annotate = document.renderer.annotate

      document.renderer.annotate = function(renderer, rows, offset, from)
        annotated[#annotated + 1] = (from or offset) - offset
        return annotate(renderer, rows, offset, from)
      end

      events.append(history, events.prompt('hi'))

      for i = 1, #text, 5 do
        events.append(history, { kind = 'thought', text = text:sub(i, i + 4) })
        document:write(blocks.build(history, nil, running))
      end

      assert.is_true(annotated[#annotated] > 0)

      local streamed = drawn(buf)
      local whole = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_win_set_buf(0, whole)
      Document(whole):write(blocks.build(history, nil, running))

      eq(drawn(whole), streamed)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_delete(whole, { force = true })
    end)

    it('draws only the header of a thought folded away, and the rest once it unfolds', function()
      local folded = true
      local running = { running = true }

      document.folded = function()
        return folded
      end

      events.append(history, events.prompt('hi'))

      for _, piece in ipairs({ 'One `a`.\n\n', '- two\n\n', 'three **b**' }) do
        events.append(history, { kind = 'thought', text = piece })
        document:write(blocks.build(history, nil, running))
      end

      local thought = document.blocks[#document.blocks]
      local function rows()
        local out = {}

        for _, mark in ipairs(marks(buf, Renderer.NAMESPACE)) do
          if mark[2] >= thought.start then out[mark[2] - thought.start] = true end
        end

        return out
      end

      eq({ [0] = true }, rows())

      local ids = vim.tbl_map(function(mark)
        return mark[1]
      end, marks(buf, Renderer.NAMESPACE))

      document:decorate_visible()

      eq(
        ids,
        vim.tbl_map(function(mark)
          return mark[1]
        end, marks(buf, Renderer.NAMESPACE))
      )
      assert.is_true(document:has_pending(thought.start, thought.finish))

      folded = false
      document:decorate_visible()

      local streamed = drawn(buf)
      local whole = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_win_set_buf(0, whole)
      Document(whole):write(blocks.build(history, nil, running))

      eq(drawn(whole), streamed)
      assert.is_false(document:has_pending(thought.start, thought.finish))
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_delete(whole, { force = true })
    end)

    it('drops a table\'s box from above once the table grows past the settled line', function()
      emit(events.prompt('hi'))
      stream('intro\n\n| a | b |\n| - | - |', 100)
      stream('\n| 1 | 2 |', 100)

      local streamed = drawn(buf)
      local whole = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_win_set_buf(0, whole)
      Document(whole):write(blocks.build(history))

      eq(drawn(whole), streamed)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_delete(whole, { force = true })
    end)

    it('draws the same marks as a reply written in one go, fences and all', function()
      local text = table.concat({
        '# Heading',
        '',
        'Some **bold** and `code`.',
        '',
        '- one',
        '- two',
        '',
        '```lua',
        'local a = 1',
        '',
        'return a',
        '```',
        '',
        '| a | b |',
        '| - | - |',
        '| 1 | 2 |',
        '',
        '> quoted',
        '',
        '| c | d |',
        '| - | - |',
        '| 3 | 4 |',
        '',
        'after the table',
        '',
        'last line',
      }, '\n')

      emit(events.prompt('hi'))
      stream(text, 7)

      local streamed = drawn(buf)
      local whole = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_win_set_buf(0, whole)
      Document(whole):write(blocks.build(history))

      eq(drawn(whole), streamed)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_delete(whole, { force = true })
    end)
  end)

  it('rewrites everything after reset', function()
    emit(events.prompt('hi'))
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].modifiable = false

    document:reset()
    document:write(blocks.build(history))

    eq({ '# untitled', '', '> hi', '' }, lines(buf))
  end)

  it('after reset rewrites only from the first line the buffer gets wrong', function()
    emit(events.prompt('one'))
    emit(events.prompt('two'))

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -2, -1, false, { 'edited' })
    vim.bo[buf].modifiable = false

    local writes = {}

    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first)
        writes[#writes + 1] = first
      end,
    })

    document:reset()
    document:write(blocks.build(history))

    eq({ #lines(buf) - 1 }, writes)
    eq('', lines(buf)[#lines(buf)])
  end)

  it('finds the block under a row', function()
    emit(events.prompt('hi'))
    emit({ kind = 'tool_call', id = 't1', title = 'Read', diffs = {} })

    eq(Block.KIND.prompt, document:block_at(2).kind)
    eq('t1', document:block_at(4).id)
  end)

  local function texts(row)
    local out = {}

    for _, mark in
      ipairs(vim.api.nvim_buf_get_extmarks(buf, Document.NAMESPACE, { row, 0 }, { row, -1 }, { details = true }))
    do
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        out[#out + 1] = chunk[1]
      end
    end

    return table.concat(out, '|')
  end

  local function diff_rows(path, status)
    local edits = EditLog(buffers.lines_of)

    history = history or {}

    local function build()
      document:write(blocks.build(history, nil, { edits = edits }))

      local block = document.blocks[3]
      local rows = {}

      for offset, line in ipairs(block.lines) do
        rows[line] = block.start + offset - 1
      end

      return block, rows
    end

    events.append(history, {
      kind = 'tool_call',
      id = 't1',
      name = 'Edit',
      status = status,
      diffs = { { path = path, old = 'local a = 1\nlocal b = 2\n', new = 'local a = 1\nlocal c = 2\n' } },
    })

    return build, build()
  end

  it('numbers an edit by where it sits in the file, coloured by its language', function()
    local path = vim.fn.tempname() .. '.lua'

    vim.fn.writefile({ '-- a', '', '', '', 'local a = 1', 'local c = 2' }, path)

    local _, block, rows = diff_rows(path, Block.STATUS.completed)

    assert.is_truthy(texts(rows['local b = 2']):find('  6 ', 1, true))
    assert.is_truthy(texts(rows['local c = 2']):find('  6 ', 1, true))
    assert.is_truthy(texts(rows['local a = 1']):find('  5 ', 1, true))
    eq(6, Block.file_line(block, rows['local c = 2']))

    local syntax = vim.tbl_filter(
      function(mark)
        return mark[4].hl_group and mark[4].hl_group:sub(1, 1) == '@'
      end,
      vim.api.nvim_buf_get_extmarks(
        buf,
        Document.NAMESPACE,
        { rows['local c = 2'], 0 },
        { rows['local c = 2'], -1 },
        { details = true }
      )
    )

    assert.is_true(#syntax > 0)
    assert.is_truthy(texts(document.blocks[2].start):find('+1', 1, true))
    vim.fn.delete(path)
  end)

  it('numbers an edit from the file before it lands while it waits for permission, then from after', function()
    local path = vim.fn.tempname() .. '.lua'

    vim.fn.writefile({ '-- a', '', 'local a = 1', 'local b = 2' }, path)

    local build, _, rows = diff_rows(path)

    assert.is_truthy(texts(rows['local c = 2']):find('  4 ', 1, true))

    vim.fn.writefile({ '-- a', '', '', 'local a = 1', 'local c = 2' }, path)
    events.append(history, { kind = 'tool_update', id = 't1', status = Block.STATUS.completed, diffs = {} })

    local _, after = build()

    assert.is_truthy(texts(after['local c = 2']):find('  5 ', 1, true))
    vim.fn.delete(path)
  end)

  it('leaves an edit unnumbered when it cannot be found in the file', function()
    local _, block, rows = diff_rows('/nowhere/a.lua')

    assert.is_falsy(texts(rows['local c = 2']):find('%d'))
    assert.is_nil(Block.file_line(block, rows['local c = 2']))
  end)

  it('folds long output and thoughts', function()
    local output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, 10)), '\n')

    emit({ kind = 'thought', text = 'a\nb' })
    emit({ kind = 'tool_call', id = 't1', name = 'Grep', category = 'search', diffs = {} })
    emit({ kind = 'tool_update', id = 't1', status = Block.STATUS.completed, output = output, diffs = {} })

    local thought, tool = document.blocks[2], document.blocks[3]

    eq('0', document:fold_level(thought.start))
    eq('>1', document:fold_level(thought.start + 1))
    eq('1', document:fold_level(thought.start + 2))
    eq('>1', document:fold_level(tool.start + 2 + require('harness.settings.transcript'):get('preview_lines')))
    eq('0', document:fold_level(tool.start + 2))
  end)

  it('ends a turn with what happened, how long it took and how many tools ran', function()
    local history_times = { 0, 1000, 13000 }

    history = {}
    events.append(history, events.prompt('go'))
    events.append(history, { kind = 'tool_call', id = 't1', name = 'Read', diffs = {} })
    events.append(history, events.stop('end_turn'))
    document:write(blocks.build(history, nil, { times = history_times }))

    assert.is_truthy(texts(document.blocks[4].start):find(' 13s · 1 tool |──', 1, true))
  end)

  it('shows a working line only while the turn runs', function()
    local status = function()
      local marks = vim.api.nvim_buf_get_extmarks(buf, Document.STATUS_NAMESPACE, 0, -1, { details = true })
      return marks[1] and marks[1][4].virt_lines[2][2][1]
    end

    history = { events.prompt('go') }
    document:write(blocks.build(history), { running = true, started = vim.uv.now() })
    eq('working', status())

    document:write(blocks.build(history), { running = false })
    eq(nil, status())
  end)

  it('marks each prompt with the prompt icon and says when one steered the turn', function()
    local function overlay(row)
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(buf, Document.NAMESPACE, { row, 0 }, { row, -1 }, { details = true }))
      do
        if mark[4].virt_text_pos == 'overlay' then return mark[4].virt_text[1][1] end
      end
    end

    history = {}
    events.append(history, events.prompt('one'))
    events.append(history, { kind = 'message', text = 'reply' })
    events.append(history, events.prompt('change course', { steered = true }))
    document:write(blocks.build(history))

    local first, reply, steered = document.blocks[2], document.blocks[3], document.blocks[4]

    eq(theme.PROMPT_ICON, overlay(first.start))
    eq(reply.start, first.finish)
    assert.is_truthy(texts(steered.start):find('steered', 1, true))
  end)

  it('says when a running turn is waiting for permission, on the tool and the working line', function()
    history = {
      events.prompt('go'),
      { kind = 'tool_call', id = 't1', name = 'Edit', title = 'Edit a.lua', status = Block.STATUS.pending, diffs = {} },
    }
    document:write(blocks.build(history), {
      running = true,
      started = vim.uv.now(),
      waiting = { { id = 't1', tool = 'Edit', title = 'Edit a.lua' } },
    })

    local status = vim.api.nvim_buf_get_extmarks(buf, Document.STATUS_NAMESPACE, 0, -1, { details = true })[1]
    local line = vim.tbl_map(function(chunk)
      return chunk[1]
    end, status[4].virt_lines[2])

    eq('waiting for you: ', line[2])
    eq('Edit a.lua', line[3])
    assert.is_truthy(texts(document.blocks[3].start):find(theme.WAITING_ICON[1], 1, true))
    assert.is_truthy(texts(document.blocks[3].start):find('waiting for you', 1, true))
  end)

  it('draws a sub-agent\'s work with a gutter, folded as one under its tool, with deeper folds inside', function()
    local output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, 10)), '\n')

    history = {}
    events.append(history, { kind = 'tool_call', id = 'task1', name = 'Task', diffs = {} })
    events.append(
      history,
      { kind = 'tool_call', id = 'inner', name = 'Grep', category = 'search', parent = 'task1', diffs = {} }
    )
    events.append(
      history,
      { kind = 'tool_update', id = 'inner', status = Block.STATUS.completed, output = output, diffs = {} }
    )
    events.append(history, { kind = 'message', text = 'report', parent = 'task1' })
    events.append(history, { kind = 'message', text = 'parent done' })
    document:write(blocks.build(history))

    local task, inner, report = document.blocks[2], document.blocks[3], document.blocks[4]

    assert.is_truthy(texts(inner.start):find(theme.BRANCH, 1, true))
    assert.is_truthy(texts(report.start):find(theme.GUTTER, 1, true))
    assert.is_falsy(texts(task.start):find(theme.GUTTER, 1, true))
    assert.is_truthy(texts(task.start):find('1 tool', 1, true))

    history[#history + 1] =
      { kind = 'tool_call', id = 'read', name = 'Read', category = 'read', parent = 'task1', diffs = {} }
    history[#history + 1] =
      { kind = 'tool_update', id = 'read', status = Block.STATUS.completed, output = 'a\nb', diffs = {} }
    document:write(blocks.build(history))

    local read

    for _, block in ipairs(document.blocks) do
      if block.id == 'read' then read = block end
    end

    eq('parent done', document.blocks[#document.blocks].lines[1])
    eq(1, read.depth)

    assert.is_truthy(texts(read.start):find(theme.BRANCH, 1, true))
    assert.is_truthy(texts(read.start):find('2 lines', 1, true))

    eq('>1', document:fold_level(inner.start))
    eq('1', document:fold_level(inner.start + 1))
    eq('>2', document:fold_level(inner.start + 2 + require('harness.settings.transcript'):get('preview_lines')))
    eq('1', document:fold_level(report.start))
    eq('0', document:fold_level(document.blocks[#document.blocks].start))
  end)
end)

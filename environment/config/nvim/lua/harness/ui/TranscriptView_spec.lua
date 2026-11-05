local Connection = require('harness.servers.acp.Connection')
local Session = require('harness.Session')
local TranscriptView = require('harness.ui.TranscriptView')
local events = require('harness.types.events')
local fake_agent = require('harness.servers.acp.fake_agent')

local eq = assert.are.same

describe('harness.ui.TranscriptView:', function()
  local session

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
  end)

  it('lays a finished edit out again when the diff layout changes and the buffer is shown', function()
    local settings = require('harness.settings.transcript')
    local saved = settings:get('diff_layout')
    local file = { 'local a = 0', 'local x = 2', 'return x' }

    session = Session({
      key = 'h' .. math.random(1e6),
      id = 's1',
      connection = Connection(fake_agent.new()),
      file_lines = function()
        return file
      end,
    })
    session:_emit(events.prompt('edit it'))
    session:_emit(events.new({
      kind = events.KIND.tool_call,
      id = 'e',
      name = 'Edit',
      status = 'completed',
      diffs = { { path = '/a.lua', old = 'local x = 1', new = 'local x = 2' } },
    }))
    session:_emit(events.stop('end_turn'))
    session:_emit(events.prompt('after'))

    for i = 1, 30 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()

    view:show_in(require('core.Window').get_current())

    local function lines()
      return table.concat(vim.api.nvim_buf_get_lines(view.bufnr, 0, -1, false), '\n')
    end

    settings:assign({ diff_layout = 'unified' })
    view:on_show()
    vim.wait(200, function()
      return not view.scheduled
    end)
    eq(nil, lines():find(' │ ', 1, true))

    settings:assign({ diff_layout = 'split' })
    view:on_show()
    vim.wait(200, function()
      return lines():find(' │ ', 1, true) ~= nil
    end)

    local split = lines():find(' │ ', 1, true) ~= nil

    settings:assign({ diff_layout = saved })
    view:dispose()

    eq(true, split)
  end)

  describe('navigating', function()
    local view

    local function tool(id, name, status)
      session:_emit(events.new({ kind = events.KIND.tool_call, id = id, name = name, status = status }))
    end

    before_each(function()
      session:_emit(events.prompt('first'))
      tool('a', 'Read', 'completed')
      session:_emit(events.new({
        kind = events.KIND.tool_call,
        id = 'b',
        name = 'Bash',
        status = 'failed',
        output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, 80)), '\n'),
      }))
      session:_emit(events.stop('end_turn'))
      session:_emit(events.prompt('second'))
      tool('c', 'Read', 'completed')
      session:_emit(events.stop('end_turn'))

      view = TranscriptView(session):mount()
      view:show_in(require('core.Window').get_current())
      view:bind(view:bindings())
      vim.wait(100, function()
        return not view.scheduled
      end)
      vim.cmd('normal! gg')
    end)

    after_each(function()
      view:dispose()
    end)

    local function row()
      return vim.api.nvim_win_get_cursor(0)[1]
    end

    local function text()
      return vim.api.nvim_get_current_line()
    end

    it('walks tool calls, and <C-o> comes back', function()
      local start = row()

      vim.cmd('normal ]t')
      local first = row()
      vim.cmd('normal 2]t')
      assert.is_true(first > start)
      assert.is_true(row() > first)

      vim.cmd('execute "normal \\<C-o>"')
      eq(first, row())
    end)

    it('lands on failed tool calls only', function()
      vim.cmd('normal ]x')
      assert.is_truthy(text():find('Bash', 1, true))
      local at = row()
      vim.cmd('normal ]x')
      eq(at, row())
    end)

    it('selects a whole turn with at', function()
      vim.cmd('normal! 3G')
      vim.cmd('normal yat')
      local yanked = vim.fn.getreg('"')
      assert.is_truthy(yanked:find('first', 1, true))
      assert.is_nil(yanked:find('second', 1, true))
    end)

    describe('while following the stream', function()
      local function stream(from, to, lines)
        for i = from, to do
          session:_emit(events.new({
            kind = events.KIND.tool_call,
            id = 's' .. i,
            name = 'Bash',
            status = 'completed',
            output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, lines or 90)), '\n'),
          }))
          vim.wait(40)
        end

        vim.wait(250)
      end

      local function at_end()
        return vim.fn.line('w$', vim.fn.bufwinid(view.bufnr)) >= vim.api.nvim_buf_line_count(view.bufnr)
      end

      before_each(function()
        vim.cmd('normal G')
        vim.wait(200)
      end)

      describe('the reader\'s cursor', function()
        local function last()
          return vim.api.nvim_buf_line_count(view.bufnr)
        end

        local function running(fn)
          session:_to('running')
          fn()
          vim.wait(400)
          session:_to('idle')
        end

        local function small(from, to)
          stream(from, to, 1)
        end

        it('stays where k put it while a turn runs and streams, and the end stays in view', function()
          small(1, 2)
          vim.cmd('normal! 3k')

          local placed = row()

          running(function()
            small(3, 4)
          end)

          eq(placed, row())
          eq(true, at_end())
        end)

        it('stays where j put it after moving back down', function()
          small(1, 2)
          vim.cmd('normal! 4k')
          vim.cmd('normal! j')

          local placed = row()

          running(function()
            small(3, 3)
          end)

          eq(placed, row())
        end)

        it('is not moved by the window being watched or the composer taking rows and giving them back', function()
          small(1, 2)
          vim.cmd('normal! 2k')

          local placed = row()

          view:watch()
          view:hold_end()
          view:keep_end()
          vim.wait(300)

          eq(placed, row())
        end)

        it('is not taken to the end by every kind of update the agent sends', function()
          small(1, 2)
          vim.cmd('normal! 3k')

          local placed = row()

          running(function()
            session:_emit(events.new({ kind = events.KIND.thought, text = 'thinking it over' }))
            vim.wait(60)
            session:_emit(events.new({ kind = events.KIND.message, text = 'a reply' }))
            vim.wait(60)
            session:_emit(events.new({
              kind = events.KIND.plan,
              entries = { { content = 'one', status = 'pending' } },
            }))
            vim.wait(60)
            session:_emit(events.new({ kind = events.KIND.tool_update, id = 's1', status = 'completed' }))
          end)

          eq(placed, row())
          eq(true, at_end())
        end)

        it('rides to the new end when it was on the last line', function()
          small(1, 2)
          vim.cmd('normal G')
          vim.wait(200)

          running(function()
            small(3, 4)
          end)

          eq(last(), row())
        end)

        it('is not sent to the end by folding all tool output', function()
          small(1, 3)
          vim.cmd('normal! 2k')
          vim.cmd('normal zT')
          vim.wait(200)

          assert.is_true(row() < last(), 'the fold keys sent the cursor to the end')
        end)
      end)

      it('keeps the end in view across tool output folded and unfolded', function()
        stream(1, 3)
        vim.cmd('normal zT')
        stream(4, 6)
        eq(true, at_end())
        vim.cmd('normal zU')
        vim.cmd('normal G')
        stream(7, 9)
        eq(true, at_end())
      end)

      it('keeps tool output folded when more output streams in, and unfolds it all after', function()
        local function closed()
          local rows = {}

          for lnum = 1, vim.api.nvim_buf_line_count(view.bufnr) do
            if vim.fn.foldclosed(lnum) == lnum then rows[#rows + 1] = lnum end
          end

          return rows
        end

        _G.test_foldexpr = function()
          return view.document:fold_level(vim.v.lnum - 1)
        end
        vim.wo.foldexpr = 'v:lua.test_foldexpr()'
        vim.cmd('normal! zR')

        stream(1, 3)
        eq(true, view:fold_tools(true))
        local folded = closed()
        assert.is_true(#folded > 0)

        stream(4, 6)

        local after = closed()
        for _, row in ipairs(folded) do
          assert.is_true(vim.tbl_contains(after, row), 'the fold at row ' .. row .. ' was reopened by the stream')
        end

        eq(true, view:fold_tools(false))
        eq({}, closed())
      end)

      it('keeps the end in view when the window gets narrower and wider', function()
        vim.cmd('vsplit')
        stream(1, 2)
        vim.cmd('vertical resize 30')
        stream(3, 4)
        eq(true, at_end())
        vim.cmd('vertical resize 100')
        stream(5, 6)
        eq(true, at_end())
        vim.cmd('only')
      end)

      it('keeps the end in view when the plan panel is shown and hidden', function()
        session:_emit(events.new({
          kind = events.KIND.plan,
          entries = { { content = 'one', status = 'pending' }, { content = 'two', status = 'pending' } },
        }))
        vim.wait(150)
        vim.cmd('normal gp')
        stream(1, 3)
        eq(true, at_end())
        vim.cmd('normal gp')
        stream(4, 6)
        eq(true, at_end())
      end)

      it('is scrolled away by a jump, and lands again on G', function()
        stream(1, 4)
        vim.cmd('normal [[')
        vim.wait(250)
        assert.is_false(at_end())
        vim.cmd('normal G')
        stream(5, 8)
        eq(true, at_end())
      end)

      it('follows a stream that ran while the transcript was hidden, then shown again', function()
        stream(1, 2)
        vim.cmd('enew')
        stream(3, 6)
        vim.cmd('buffer ' .. view.bufnr)
        vim.wait(250)
        stream(7, 8)
        eq(true, at_end())
      end)
    end)

    it('hints the keys of the block under the cursor', function()
      local hints = require('harness.ui.hints')

      vim.cmd('normal! 3G')
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = view.bufnr })

      local marks = vim.api.nvim_buf_get_extmarks(view.bufnr, hints.NAMESPACE, 0, -1, { details = true })

      eq(1, #marks)
      assert.is_truthy(marks[1][4].virt_text[1][1]:find('fork', 1, true))

      vim.cmd('normal! 1G')
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = view.bufnr })
      eq(0, #vim.api.nvim_buf_get_extmarks(view.bufnr, hints.NAMESPACE, 0, -1, {}))
    end)

    it('lists every key on g?', function()
      vim.cmd('normal g?')

      local surfaces = require('surfaces')
      local found = false

      for _, surface in ipairs(surfaces.all()) do
        if surface.title == 'Harness keys' then found = true end
      end

      surfaces.close_all()
      eq(true, found)
    end)

    it('folds every tool output and opens it again', function()
      local function closed()
        local count = 0

        for lnum = 1, vim.api.nvim_buf_line_count(view.bufnr) do
          if vim.fn.foldclosed(lnum) == lnum then count = count + 1 end
        end

        return count
      end

      _G.test_foldexpr = function()
        return view.document:fold_level(vim.v.lnum - 1)
      end
      vim.wo.foldexpr = 'v:lua.test_foldexpr()'
      vim.cmd('normal! zR')
      eq(0, closed())
      vim.cmd('normal zT')
      assert.is_true(closed() > 0)
      vim.cmd('normal zU')
      eq(0, closed())
    end)
  end)

  it('names the buffer after the session', function()
    eq('harness://h1 untitled', TranscriptView.buffer_name({ key = 'h1' }))
  end)

  it('creates a listed, unmodifiable harness buffer that renders on mount', function()
    session:_emit(events.prompt('hi'))

    local view = TranscriptView(session):mount()

    eq(TranscriptView.FILETYPE, vim.bo[view.bufnr].filetype)
    eq(false, vim.bo[view.bufnr].modifiable)
    eq('> hi', vim.api.nvim_buf_get_lines(view.bufnr, 2, 3, false)[1])
    view:dispose()
  end)

  it('styles each window it is shown in, with folds driven by the document', function()
    local view = TranscriptView(session):mount()

    vim.api.nvim_win_set_buf(0, view.bufnr)

    local win = vim.api.nvim_get_current_win()

    eq('expr', vim.wo[win].foldmethod)
    eq(2, vim.wo[win].conceallevel)
    assert.truthy(vim.wo[win].winbar:find('write to this session', 1, true))
    eq(true, view:is_visible())
    view:dispose()
  end)

  it('opens empty rows under the newest line only once the stream reaches the bottom of the window', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()

    view:show_in(require('core.Window').get_current())

    local win = vim.api.nvim_get_current_win()
    local margin =
      math.min(require('harness.settings.composer'):get('height'), math.floor(vim.api.nvim_win_get_height(win) / 3))

    local function room()
      local last = vim.api.nvim_buf_line_count(view.bufnr)

      return vim.api.nvim_win_call(win, vim.fn.winsaveview).topline + vim.api.nvim_win_get_height(win) - 1 - last
    end

    local initial = room()

    assert.is_true(margin > 0)
    assert.is_true(initial >= margin)

    for i = 1, 20 do
      session:_emit(events.new({ kind = events.KIND.message, text = 'line ' .. i .. '\n\n' }))
    end

    view:render()
    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    assert.is_true(room() >= 0)

    local top = vim.fn.line('w0', win)

    session:_emit(events.new({ kind = events.KIND.message, text = 'one more\n\n' }))
    view:render()
    assert.is_true(room() >= 0)
    assert.is_true(room() >= margin - 3 or vim.fn.line('w0', win) == top)
    view:dispose()
  end)

  it('lands on the end when shown, decorating only around there', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()

    view:show_in(require('core.Window').get_current())

    local win = vim.api.nvim_get_current_win()
    local document = require('harness.ui.Document')

    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    eq({}, vim.api.nvim_buf_get_extmarks(view.bufnr, document.NAMESPACE, 0, { 3, 0 }, {}))
    assert.is_true(
      #vim.api.nvim_buf_get_extmarks(
          view.bufnr,
          document.NAMESPACE,
          { view.document.blocks[#view.document.blocks].start, 0 },
          -1,
          {}
        ) > 0
    )
    view:dispose()
  end)

  it('shows a finished session from the end', function()
    for i = 1, 40 do
      session:_emit(events.prompt('turn ' .. i))
      session:_emit(events.new({ kind = 'message', text = 'answer ' .. i .. '\n\nmore ' .. i }))
      session:_emit(events.new({ kind = 'stop', reason = 'end_turn' }))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())

    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    view:dispose()
  end)

  it('lands on the end again when a stored session finishes loading', function()
    for i = 1, 40 do
      session:_emit(events.prompt('turn ' .. i))
      session:_emit(events.new({ kind = 'message', text = 'answer ' .. i .. '\n\nmore ' .. i }))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())
    vim.cmd('normal! gg')
    session:_notify({ kind = events.NOTICE.loaded })
    view:render()
    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    view:dispose()
  end)

  it('follows a prompt sent from here to the end, then keeps the reply in view', function()
    for i = 1, 30 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())
    view:render()

    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])

    session:_emit(events.prompt('next'))
    view:render()

    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    assert.is_true(sticky_bottom.at_end(Window(win)))

    session:_emit(events.new({ kind = 'message', text = 'one\n\ntwo\n\nthree' }))
    view:render()

    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    assert.is_true(sticky_bottom.at_end(Window(win)))
    view:dispose()
  end)

  it('scrolls the reply up as it grows past the window, keeping the end in view', function()
    for i = 1, 30 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())
    session:_emit(events.prompt('next'))
    view:render()

    local top = vim.fn.line('w0', win)
    local height = vim.api.nvim_win_get_height(win)

    session:_emit(events.new({ kind = 'message', text = string.rep('\n\nmore', height) }))
    view:render()

    assert.is_true(vim.fn.line('w0', win) > top)
    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    assert.is_true(sticky_bottom.at_end(Window(win)))
    view:dispose()
  end)

  it('leaves a scrolled-up window alone when a prompt arrives, and follows again when it lands', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')

    view:show_in(Window.get_current())
    vim.cmd('normal! gg')
    session:_emit(events.prompt('next'))
    session:_emit(events.new({ kind = 'message', text = 'reply' }))
    view:render()
    eq(1, vim.fn.line('w0', win))
    eq(1, vim.api.nvim_win_get_cursor(win)[1])

    view:land(Window.get_current())
    session:_emit(events.new({ kind = 'message', text = string.rep('\n\nmore', vim.api.nvim_win_get_height(win)) }))
    view:render()
    eq(true, require('harness.ui.sticky_bottom').at_end(Window(win)))
    view:dispose()
  end)

  it('follows the stream that ran while hidden when it was left at the end', function()
    for i = 1, 30 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())
    vim.cmd('enew')
    session:_emit(events.new({ kind = 'message', text = string.rep('\n\nmore', 80) }))
    view:render()
    vim.api.nvim_win_set_buf(win, view.bufnr)
    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    assert.is_true(vim.fn.line('w$', win) >= vim.api.nvim_buf_line_count(view.bufnr))
    view:dispose()
  end)

  it('leaves a window alone when it was left scrolled away from the end', function()
    for i = 1, 30 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())
    vim.cmd('normal! gg')
    vim.cmd('enew')
    session:_emit(events.new({ kind = 'message', text = 'later' }))
    view:render()
    vim.api.nvim_win_set_buf(win, view.bufnr)
    eq(1, vim.api.nvim_win_get_cursor(win)[1])
    view:dispose()
  end)

  it('does not pull a window back down once it has scrolled away from the end', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())
    vim.cmd('normal! ' .. (require('harness.ui.sticky_bottom').margin(require('core.Window')(win)) + 3) .. '\25')

    local top = vim.fn.line('w0', win)

    session:_emit(events.new({ kind = 'message', text = 'more' }))
    view:render()
    eq(top, vim.fn.line('w0', win))
    view:dispose()
  end)

  it('does not move a window when no text arrives', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())
    vim.cmd('normal! 3\25')

    local top = vim.fn.line('w0', win)

    eq(true, sticky_bottom.at_end(Window(win)))

    view:render()
    view:watch()

    eq(top, vim.fn.line('w0', win))
    eq(false, view.following:follows(Window(win)))
    view:dispose()
  end)

  it('takes the stream back up when the end is scrolled back into view', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())
    vim.cmd('normal! ' .. (sticky_bottom.margin(Window(win)) + 3) .. '\25')
    view:watch()
    eq(false, view.following:follows(Window(win)))

    vim.cmd('normal! G')
    vim.cmd('normal! ' .. (sticky_bottom.margin(Window(win)) + 1) .. '\5')

    session:_emit(events.new({ kind = 'message', text = 'more' }))
    view:render()

    eq(true, view.following:follows(Window(win)))
    assert.is_true(sticky_bottom.at_end(Window(win)))
    view:dispose()
  end)

  it('takes the stream back up when the end is scrolled back to the bottom', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())
    vim.cmd('normal! ' .. (sticky_bottom.margin(Window(win)) + 3) .. '\25')
    view:watch()
    eq(false, view.following:follows(Window(win)))

    vim.cmd('normal! G')

    session:_emit(events.new({ kind = 'message', text = 'more' }))
    view:render()

    eq(true, view.following:follows(Window(win)))
    assert.is_true(sticky_bottom.at_end(Window(win)))
    view:dispose()
  end)

  it('leaves a window scrolled up alone while the newest line is still in view', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())

    vim.cmd('normal! 3\25')

    local scrolled = vim.fn.line('w0', win)

    eq(true, sticky_bottom.at_end(Window(win)))

    session:_emit(events.new({ kind = 'message', text = 'more' }))
    view:render()

    eq(scrolled, vim.fn.line('w0', win))
    eq(false, view.following:follows(Window(win)))
    view:dispose()
  end)

  it('notices the window being scrolled, without waiting for an event', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')

    view:show_in(Window.get_current())
    vim.wait(100)
    vim.cmd('normal! ' .. (require('harness.ui.sticky_bottom').margin(Window(win)) + 3) .. '\25')

    local top = vim.fn.line('w0', win)

    assert.is_true(vim.wait(1000, function()
      return not view.following:follows(Window(win))
    end))

    session:_emit(events.new({ kind = 'message', text = 'more' }))
    view:render()

    eq(top, vim.fn.line('w0', win))
    view:dispose()
  end)

  it('places the end again after decorating it on landing, so nothing shifts afterwards', function()
    for i = 1, 100 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')
    local decorate = view.document.decorate_visible

    view.document.decorate_visible = function(self)
      if not view.grown then
        view.grown = true

        local last = vim.api.nvim_buf_line_count(view.bufnr)

        vim.api.nvim_buf_set_extmark(view.bufnr, vim.api.nvim_create_namespace('spec'), last - 4, 0, {
          virt_lines = { { { 'a' } }, { { 'b' } }, { { 'c' } } },
        })
      end

      return decorate(self)
    end

    view:show_in(Window.get_current())

    local function shown()
      return Window(win):get_text_height(vim.fn.line('w0', win) - 1, vim.api.nvim_buf_line_count(view.bufnr) - 1)
    end

    local landed, top = shown(), vim.fn.line('w0', win)

    sticky_bottom.pin(Window(win))
    eq(landed, shown())
    eq(top, vim.fn.line('w0', win))
    view:dispose()
  end)

  it('writes a stored session in one go once it has loaded, then lands on the end', function()
    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())
    session.state = 'loading'
    view:render()

    local before = vim.api.nvim_buf_line_count(view.bufnr)

    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    view:render()
    eq(before, vim.api.nvim_buf_line_count(view.bufnr))
    eq(1, vim.fn.line('w0', win))

    session.state = 'idle'
    session:_notify({ kind = events.NOTICE.loaded })
    view:render()
    assert.is_true(vim.api.nvim_buf_line_count(view.bufnr) > before)
    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    view:dispose()
  end)

  it('lands on the end in a window that has never shown it', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()

    view:show_in(require('core.Window').get_current())
    vim.cmd('normal! gg')
    vim.cmd('tabnew')

    local win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_buf(win, view.bufnr)
    eq(vim.api.nvim_buf_line_count(view.bufnr), vim.api.nvim_win_get_cursor(win)[1])
    view:dispose()
  end)

  it('follows the stream in a second window that came to show it without BufWinEnter', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local Window = require('core.Window')

    view:show_in(Window.get_current())

    local first = vim.api.nvim_get_current_win()

    vim.cmd('noautocmd vsplit')

    local second = vim.api.nvim_get_current_win()

    eq(false, view.following:settled(Window(second)))
    view:watch()
    eq(true, view.following:settled(Window(second)))
    eq(true, view.following:follows(Window(second)))

    vim.api.nvim_win_call(first, function()
      vim.cmd('normal! 6\25')
    end)
    view:watch()

    local function top_text()
      local row = vim.fn.line('w0', first)

      return vim.api.nvim_buf_get_lines(view.bufnr, row - 1, row, false)[1]
    end

    local top = top_text()

    session:_emit(events.new({ kind = 'message', text = string.rep('more rows\n\n', 30) }))
    view:render()

    eq(top, top_text())
    eq(true, require('harness.ui.sticky_bottom').at_end(Window(second)))
    view:dispose()
  end)

  it('puts the end back in view when rows grow under a window that follows it', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')

    view:show_in(Window.get_current())

    local last = vim.api.nvim_buf_line_count(view.bufnr)
    local rows = {}

    for i = 1, vim.api.nvim_win_get_height(win) do
      rows[i] = { { 'row' } }
    end

    vim.api.nvim_buf_set_extmark(view.bufnr, vim.api.nvim_create_namespace('spec'), last - 2, 0, { virt_lines = rows })
    eq(false, require('harness.ui.sticky_bottom').at_end(Window(win)))
    view:keep_end()
    eq(true, require('harness.ui.sticky_bottom').at_end(Window(win)))
    view:dispose()
  end)

  it('keeps the end in view when the window shrinks', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')

    view:show_in(Window.get_current())
    vim.cmd('new')
    vim.api.nvim_win_set_height(win, math.floor(vim.api.nvim_win_get_height(win) / 3))
    view:keep_end()
    eq(true, require('harness.ui.sticky_bottom').at_end(Window(win)))
    view:dispose()
  end)

  it('opens a split below into the empty rows without moving the text', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local composer = require('harness.ui.composer')
    local view = TranscriptView(session, { composer = composer }):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())

    local is_open = composer.is_open

    composer.is_open = function()
      return true
    end

    local top, room = vim.fn.line('w0', win), sticky_bottom.room(Window(win))

    local height = vim.api.nvim_win_get_height(win)

    vim.cmd('belowright 2new')

    local lost = height - vim.api.nvim_win_get_height(win)

    assert.is_true(lost <= room)
    view:hold_end()
    eq(top, vim.fn.line('w0', win))
    eq(room - lost, sticky_bottom.room(Window(win)))

    vim.cmd('close')
    view:hold_end()
    eq(top, vim.fn.line('w0', win))
    eq(room, sticky_bottom.room(Window(win)))
    composer.is_open = is_open
    view:dispose()
  end)

  it('moves the text by only the rows a taller split takes beyond the empty ones', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local composer = require('harness.ui.composer')
    local view = TranscriptView(session, { composer = composer }):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())

    local is_open = composer.is_open

    composer.is_open = function()
      return true
    end

    local top, room = vim.fn.line('w0', win), sticky_bottom.room(Window(win))

    local height = vim.api.nvim_win_get_height(win)

    vim.cmd('belowright ' .. (room + 2) .. 'new')

    local lost = height - vim.api.nvim_win_get_height(win)

    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(view.bufnr), 0 })
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = top })
    end)
    view:hold_end()
    assert.is_true(lost > room)
    assert.is_true(vim.fn.line('w0', win) > top)
    assert.is_true(sticky_bottom.room(Window(win)) >= 0)
    assert.is_true(sticky_bottom.room(Window(win)) <= 2)
    composer.is_open = is_open
    view:dispose()
  end)

  it('does not bounce the text when the composer height setting shrinks', function()
    local composer = require('harness.settings.composer')
    local saved = composer:get('height')

    composer:set('height', 4)
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()
    local Window = require('core.Window')
    local sticky_bottom = require('harness.ui.sticky_bottom')

    view:show_in(Window.get_current())

    composer:set('height', 1)
    view:sync()

    local top = vim.fn.line('w0', win)

    for _ = 1, 3 do
      view:sync()
      eq(top, vim.fn.line('w0', win))
    end

    assert.is_true(sticky_bottom.room(Window(win)) >= 1)

    composer:set('height', saved)
    view:dispose()
  end)

  it('shows that a stored session is reloading, without redrawing what is already there', function()
    for i = 1, 10 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local lines = vim.api.nvim_buf_get_lines(view.bufnr, 0, -1, false)
    local document = require('harness.ui.Document')

    session.state = 'reloading'
    view:render()
    eq(lines, vim.api.nvim_buf_get_lines(view.bufnr, 0, -1, false))

    local marks = vim.api.nvim_buf_get_extmarks(view.bufnr, document.STATUS_NAMESPACE, 0, -1, { details = true })
    local text = ''

    for _, mark in ipairs(marks) do
      for _, line in ipairs(mark[4].virt_lines or {}) do
        for _, chunk in ipairs(line) do
          text = text .. chunk[1]
        end
      end
    end

    assert.truthy(text:find('loading', 1, true))
    session.state = 'idle'
    view:dispose()
  end)

  it('leaves a window alone that was scrolled away when it was left, however it was left', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    vim.fn.winrestview({ topline = 1 })
    eq(1, vim.fn.line('w0', win))
    view:watch()
    vim.cmd('tabnew')
    vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, true))
    vim.api.nvim_win_set_buf(win, view.bufnr)
    eq(1, vim.api.nvim_win_get_cursor(win)[1])
    view:dispose()
  end)

  it('does not put the end back for a window the user scrolled away', function()
    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()
    local win = vim.api.nvim_get_current_win()

    view:show_in(require('core.Window').get_current())
    vim.cmd('normal! gg')
    view:keep_end()
    eq(1, vim.fn.line('w0', win))
    view:dispose()
  end)

  it('lets go of the session, its timer and its autocmds when disposed', function()
    local view = TranscriptView(session):mount()
    local group = view.group.id

    view:dispose()
    view:dispose()

    eq({}, session._listeners)
    eq(false, view.timer:is_active())
    eq(false, view.watcher:is_active())
    eq(false, pcall(vim.api.nvim_get_autocmds, { group = group }))
  end)

  it('collapses old turns until expanded, then shows them all', function()
    local settings = require('harness.settings.transcript')
    local saved = settings:get('live_turns')

    settings:set('live_turns', 2)

    for i = 1, 5 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local view = TranscriptView(session):mount()

    eq('collapsed', view.document.blocks[2].kind)
    assert.is_true(view:expand())
    assert.is_false(view:expand())
    eq('> turn 1', vim.api.nvim_buf_get_lines(view.bufnr, 2, 3, false)[1])

    settings:set('live_turns', saved)
    view:dispose()
  end)

  it('renders a burst of updates once a frame, ending on the latest', function()
    local view = TranscriptView(session):mount()
    local renders = 0
    local render = view.render

    view.render = function(...)
      renders = renders + 1
      return render(...)
    end

    for i = 1, 5 do
      session:_emit(events.prompt('turn ' .. i))
    end

    eq(true, view.scheduled)
    vim.wait(200, function()
      return not view.scheduled
    end)

    eq(1, renders)
    assert.is_true(vim.tbl_contains(vim.api.nvim_buf_get_lines(view.bufnr, 0, -1, false), '> turn 5'))
    view:dispose()
  end)

  it('drops a paced render once the view has rendered or gone', function()
    local view = TranscriptView(session):mount()
    local renders = 0
    local render = view.render

    view.render = function(...)
      renders = renders + 1
      return render(...)
    end

    session:_emit(events.prompt('one'))
    view:render()
    vim.wait(50)

    eq(1, renders)

    session:_emit(events.prompt('two'))
    view:dispose()
    vim.wait(50)

    eq(1, renders)
  end)

  it('lists the tool calls whose sub-agents are still running', function()
    local active = TranscriptView.active_subagents({
      children = {
        c1 = { tool = 'A', state = 'running' },
        c2 = { tool = 'B', state = 'idle' },
        c3 = { state = 'running' },
      },
    })

    eq({ A = true }, active)
    eq({}, TranscriptView.active_subagents({}))
  end)
end)

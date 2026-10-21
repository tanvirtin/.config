local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local events = require('harness.events')
local fake_agent = require('harness.fake_agent')
local jsonrpc = require('harness.acp.jsonrpc')
local transcript = require('harness.ui.transcript')
local blocks_preview = require('harness.settings.transcript'):get('preview_lines')

local eq = assert.are.same

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

describe('harness.ui.transcript:', function()
  describe('render', function()
    it('shows prompts, replies, thoughts, tool calls and the end of a turn', function()
      eq(
        {
          '# Harness',
          '',
          '> what is here?',
          '> be brief',
          '',
          'Looking',
          '',
          '-> buffer_read',
          '',
          '> [!thought]',
          '> checking',
          '',
          'It has two',
          'lines.',
          '',
          '*end_turn*',
          '',
        },
        transcript.render({
          events.prompt('what is here?\nbe brief'),
          { kind = 'message', text = 'Looking' },
          { kind = 'tool_call', id = 't1', title = 'buffer_read', diffs = {} },
          { kind = 'thought', text = 'checking' },
          { kind = 'message', text = 'It has two\nlines.' },
          events.stop('end_turn'),
        })
      )
    end)

    it('shows a new file\'s diff', function()
      local out = table.concat(
        transcript.render({
          {
            kind = 'tool_call',
            id = 't1',
            title = 'Write',
            diffs = { { path = '/new.lua', old = '', new = 'x = 1' } },
          },
        }),
        '\n'
      )

      assert.is_truthy(out:find('--- /new.lua', 1, true))
      assert.is_truthy(out:find('+x = 1', 1, true))
    end)

    it('never puts a newline inside a buffer line', function()
      local lines = transcript.render({
        { kind = 'tool_call', id = 't1', title = 'Bash: for f in *; do\n  echo $f\ndone', diffs = {} },
        { kind = 'tool_update', id = 't2', title = 'Read\nfile', status = 'failed', diffs = {} },
        { kind = 'plan', entries = { { content = 'first\nsecond', status = 'completed' } } },
        events.permission('Bash\nrm', false),
        events.error('boom\nstack traceback:\n  here'),
      }, 'Two\nlines')

      for _, line in ipairs(lines) do
        assert.is_falsy(line:find('\n', 1, true), line)
      end

      eq('# Two lines', lines[1])
      assert.is_truthy(vim.tbl_contains(lines, '-> Bash: for f in *; do echo $f done'))
      assert.is_truthy(vim.tbl_contains(lines, 'stack traceback:'))

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('titles the transcript and drops the context from replayed prompts', function()
      eq(
        { '# Rename x', '', '> rename x', '' },
        transcript.render(
          { { kind = 'user', text = '<editor-context>at a.lua</editor-context>\n\nrename x' } },
          'Rename x'
        )
      )
    end)

    it('shows diffs once per tool call, plans, refusals, failures and errors', function()
      local diff = { path = '/a.lua', old = 'local x = 1', new = 'local y = 1' }
      local out = table.concat(
        transcript.render({
          { kind = 'plan', entries = { { content = 'rename', status = 'completed' }, { content = 'test' } } },
          { kind = 'tool_call', id = 't1', title = 'Edit a.lua', diffs = { diff } },
          { kind = 'tool_update', id = 't1', status = 'completed', diffs = { diff } },
          events.permission('Bash', false),
          events.permission('Read', true),
          { kind = 'tool_update', id = 't2', title = 'Bash', status = 'failed', diffs = {} },
          events.error('not logged in'),
        }),
        '\n'
      )

      assert.is_truthy(out:find('plan\n- [x] rename\n- [ ] test', 1, true))
      assert.is_truthy(out:find('```diff\n--- /a.lua', 1, true))
      assert.is_truthy(out:find('-local x = 1\n+local y = 1', 1, true))
      eq(1, select(2, out:gsub('```diff', '')))
      assert.is_truthy(out:find('refused: Bash', 1, true))
      eq(nil, out:find('Read', 1, true))
      assert.is_truthy(out:find('failed: Bash', 1, true))
      assert.is_truthy(out:find('error: not logged in', 1, true))
    end)
  end)

  describe('open', function()
    local session

    local function new_session()
      return Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
    end

    before_each(function()
      vim.cmd('silent! tabonly!')
      vim.cmd('silent! only!')
      vim.cmd('enew!')
      session = new_session()
    end)

    it('shows the session full screen in the current window and follows its events', function()
      local win = vim.api.nvim_get_current_win()
      local buf = transcript.open(session)

      eq(1, #vim.api.nvim_tabpage_list_wins(0))
      eq(win, vim.api.nvim_get_current_win())
      eq(buf, vim.api.nvim_win_get_buf(win))
      eq(true, vim.bo[buf].buflisted)
      eq(true, vim.wo[win].wrap)
      eq(session, transcript.view(buf).session)
      eq(transcript.view(buf), transcript.last())

      session:_emit(events.prompt('hi'))
      vim.wait(1000, function()
        return lines(buf)[3] == '> hi'
      end)

      eq({ '# Harness', '', '> hi', '' }, lines(buf))
    end)

    it('opens with the cursor at the bottom, and keeps it there as the reply streams', function()
      for i = 1, 30 do
        session:_emit(events.prompt('earlier ' .. i))
      end

      local buf = transcript.open(session)

      eq(vim.api.nvim_buf_line_count(buf), vim.api.nvim_win_get_cursor(0)[1])

      session:_emit({ kind = 'message', text = 'streaming\nmore\nlines' })
      vim.wait(1000, function()
        return lines(buf)[#lines(buf)] == 'lines'
      end)

      eq(vim.api.nvim_buf_line_count(buf), vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('leaves the cursor alone when the user has scrolled up to read', function()
      for i = 1, 30 do
        session:_emit(events.prompt('earlier ' .. i))
      end

      local buf = transcript.open(session)

      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      session:_emit({ kind = 'message', text = 'new text' })
      vim.wait(1000, function()
        return lines(buf)[#lines(buf)] == 'new text'
      end)

      eq(5, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('is a buffer like any other: switching back restores the window', function()
      local code = vim.api.nvim_get_current_buf()
      local buf = transcript.open(session)

      vim.cmd('buffer ' .. code)
      eq(code, vim.api.nvim_get_current_buf())

      vim.cmd('buffer ' .. buf)
      eq(buf, vim.api.nvim_get_current_buf())

      local other = transcript.open(new_session())

      assert.is_true(other ~= buf)
      eq(other, vim.api.nvim_get_current_buf())
      eq(1, #vim.api.nvim_tabpage_list_wins(0))
    end)

    it('names the buffer after the session and its title', function()
      local buf = transcript.open(session)

      assert.is_truthy(vim.api.nvim_buf_get_name(buf):find('harness://' .. session.key .. ' untitled', 1, true))

      session:_emit({ kind = 'title', title = 'Fix the picker' })
      session.title = 'Fix the picker'
      session:_emit({ kind = 'title', title = 'Fix the picker' })

      assert.is_truthy(vim.api.nvim_buf_get_name(buf):find('Fix the picker', 1, true))
    end)

    it('is read-only, and its insert keys open the composer for it', function()
      local buf = transcript.open(session)

      eq(false, vim.bo[buf].modifiable)
      assert.is_truthy(vim.wo.winbar:find('write to this session', 1, true))

      for _, key in ipairs({ 'i', 'a', 'o', 'I', 'A', 'O' }) do
        eq('Write to this session', vim.fn.maparg(key, 'n', false, true).desc)
      end
    end)

    it('only creates the buffer in the background', function()
      local buf = transcript.open(session, { background = true })

      eq(1, #vim.api.nvim_tabpage_list_wins(0))
      eq(nil, (transcript.window()))
      eq(true, vim.api.nvim_get_current_buf() ~= buf)
      eq(session, transcript.view(buf).session)
    end)

    it('rebuilds the buffer from history when it is shown again', function()
      session:_emit(events.prompt('earlier'))

      local buf = transcript.open(session)

      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      vim.cmd('enew')
      transcript.open(session)

      eq('> earlier', lines(buf)[3])
    end)

    it('keeps the session when its buffer is wiped', function()
      local buf = transcript.open(session)

      vim.api.nvim_buf_delete(buf, { force = true })

      eq(nil, transcript.view(buf))
      eq({}, session._listeners)
      eq('idle', session.state)

      local again = transcript.open(session)

      assert.is_truthy(again ~= buf)
      eq(session, transcript.view(again).session)
    end)

    it('comes back working after :bdelete, which strips buffer keymaps', function()
      session:_emit(events.prompt('before the delete'))

      local buf = transcript.open(session)

      vim.cmd('enew')
      vim.cmd('bdelete ' .. buf)
      vim.wait(50)

      eq(false, vim.api.nvim_buf_is_valid(buf))
      eq({}, session._listeners)

      local again = transcript.open(session)

      eq('Write to this session', vim.fn.maparg('i', 'n', false, true).desc)
      eq('> before the delete', lines(again)[3])
      assert.is_truthy(vim.api.nvim_buf_get_name(again):find('harness://' .. session.key, 1, true))
    end)

    it('shows the session state, context use and cost in the winbar', function()
      transcript.open(session)
      session:_emit({ kind = 'usage', used = 250, size = 1000, cost = 1.5 })
      vim.wait(1000, function()
        return vim.wo.winbar:find('ctx', 1, true) ~= nil
      end)

      assert.is_truthy(vim.wo.winbar:find('○ idle', 1, true))
      assert.is_truthy(vim.wo.winbar:find('ctx 25%%', 1, true))
      assert.is_truthy(vim.wo.winbar:find('$1.50', 1, true))
    end)

    it('opens the file a reply names in a new tab on <CR>, and jumps between turns', function()
      local dir = vim.fn.tempname()

      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'a', 'b', 'c' }, dir .. '/x.lua')
      session.dir = dir
      session:_emit(events.prompt('first'))
      session:_emit({ kind = 'message', text = 'see `x.lua:2`' })
      session:_emit(events.stop('end_turn'))
      session:_emit(events.prompt('second'))

      local buf = transcript.open(session)
      local row

      for i, line in ipairs(lines(buf)) do
        if line == 'see `x.lua:2`' then row = i end
      end

      vim.api.nvim_win_set_cursor(0, { row, 6 })
      vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

      eq(vim.uv.fs_realpath(dir .. '/x.lua'), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
      eq(2, vim.api.nvim_win_get_cursor(0)[1])

      vim.cmd('bwipeout')
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_feedkeys(']]', 'x', false)
      eq('> first', vim.api.nvim_get_current_line())
      vim.api.nvim_feedkeys(']]', 'x', false)
      eq('> second', vim.api.nvim_get_current_line())
      vim.api.nvim_feedkeys('[[', 'x', false)
      eq('> first', vim.api.nvim_get_current_line())
      vim.fn.delete(dir, 'rf')
    end)

    it('folds long output closed, and keeps the fold in place when the whole buffer is rewritten', function()
      local output = table.concat(vim.tbl_map(tostring, vim.fn.range(1, 20)), '\n')
      local buf = transcript.open(session)

      session:_emit({ kind = 'tool_call', id = 't1', name = 'Bash', category = 'execute', diffs = {} })
      session:_emit({ kind = 'tool_update', id = 't1', status = 'completed', output = output, diffs = {} })

      local function fold_start()
        vim.wait(1000, function()
          return #lines(buf) > 20
        end)

        for i, line in ipairs(lines(buf)) do
          if vim.fn.foldclosed(i) == i then return line end
        end
      end

      eq(tostring(blocks_preview + 1), fold_start())

      session.title = 'Renamed'
      session:_emit({ kind = 'title', title = 'Renamed' })
      vim.wait(1000, function()
        return lines(buf)[1] == '# Renamed'
      end)

      eq(tostring(blocks_preview + 1), fold_start())
    end)

    it('animates a running turn without errors, and clears the working line when it ends', function()
      local errors = {}
      local notify = vim.notify

      vim.notify = function(msg)
        errors[#errors + 1] = msg
      end

      local buf = transcript.open(session)
      local Document = require('harness.ui.document')
      local function status()
        return #vim.api.nvim_buf_get_extmarks(buf, Document.STATUS_NAMESPACE, 0, -1, {})
      end

      session.state = 'running'
      session:_emit(events.prompt('go'))
      session:_emit({ kind = 'tool_call', id = 't1', name = 'Bash', status = 'pending', diffs = {} })

      local ok, err = pcall(vim.wait, require('harness.settings.transcript'):get('tick_ms') * 4, function()
        return false
      end)

      eq(true, ok, err)
      eq(1, status())

      session.state = 'idle'
      session:_emit(events.stop('end_turn'))
      vim.wait(require('harness.settings.transcript'):get('tick_ms') * 3, function()
        return status() == 0
      end)

      vim.notify = notify
      eq(0, status())
      eq({}, errors)
    end)

    it('yanks the code block under the cursor without its fences, or else the whole block', function()
      session:_emit(events.prompt('show me'))
      session:_emit({ kind = 'message', text = 'Here:\n\n```lua\nlocal x = 1\nreturn x\n```\n\nDone.' })
      session:_emit(events.stop('end_turn'))

      local buf = transcript.open(session)
      local rows = {}

      for i, line in ipairs(lines(buf)) do
        rows[line] = i
      end

      vim.api.nvim_win_set_cursor(0, { rows['return x'], 0 })
      vim.api.nvim_feedkeys('gy', 'x', false)
      eq({ 'local x = 1', 'return x' }, vim.fn.getreg('"', 1, true))
      eq('V', vim.fn.getregtype('"'))

      vim.api.nvim_win_set_cursor(0, { rows['Done.'], 0 })
      eq({ 'Here:', '', '```lua', 'local x = 1', 'return x', '```', '', 'Done.' }, (transcript.yank(buf, 'a')))

      vim.api.nvim_win_set_cursor(0, { rows['> show me'], 0 })
      eq({ 'show me' }, (transcript.yank(buf, 'a')))
    end)

    it('shows when the session is also being driven by another program', function()
      local follow = require('harness.follow')

      transcript.open(session)
      follow.start(session)
      session.external = vim.uv.now()
      session:_notify({ kind = 'external' })
      vim.wait(500, function()
        return vim.wo.winbar:find('external', 1, true) ~= nil
      end)

      assert.is_truthy(vim.wo.winbar:find('⇄ external', 1, true))
      follow.stop(session)
    end)

    it('tells you a session is waiting for permission only when its transcript is out of sight', function()
      local messages = {}
      local notify = vim.notify

      vim.notify = function(message)
        messages[#messages + 1] = message
      end

      local buf = transcript.open(session)

      session._pending[{ tool = 'Edit', id = 't1', title = 'Edit a.lua' }] = true
      transcript.announce_waiting(session, buf)
      vim.wait(50)
      eq({}, messages)

      vim.cmd('enew')
      transcript.announce_waiting(session, buf)
      vim.wait(50)
      vim.notify = notify

      eq(1, #messages)
      assert.is_truthy(messages[1]:find('waiting for your permission: Edit a.lua', 1, true))
      session._pending = {}
    end)

    it('shows the mode and model in the winbar, and cycles the mode with <S-Tab>', function()
      local buf = transcript.open(session)
      local cycled = 0

      session:configure({
        configOptions = {
          { id = 'mode', category = 'mode', currentValue = 'plan', options = { { value = 'plan', name = 'Plan' } } },
          { id = 'model', category = 'model', currentValue = 'opus', options = { { value = 'opus', name = 'Opus' } } },
        },
      })
      session.cycle_mode = function()
        cycled = cycled + 1
      end
      vim.wait(500, function()
        return vim.wo.winbar:find('Plan', 1, true) ~= nil
      end)

      assert.is_truthy(vim.wo.winbar:find('[Plan]', 1, true))
      assert.is_truthy(vim.wo.winbar:find('Opus', 1, true))

      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_feedkeys(vim.keycode('<S-Tab>'), 'x', false)
      eq(1, cycled)
    end)

    describe('asking for permission in the transcript', function()
      local permissions = require('harness.permissions')
      local Document = require('harness.ui.document')
      local async = require('harness.async')
      local prompt_id, agent

      local function asking_session()
        agent = fake_agent.new({
          ['session/prompt'] = function(message)
            prompt_id = message.id
            return { fake_agent.permission('s1', 'Edit') }
          end,
          reply = function(message)
            if message.id ~= 'perm-1' then return {} end
            return { jsonrpc.result(prompt_id, { stopReason = 'end_turn' }) }
          end,
        })

        return Session({
          key = 'hp' .. math.random(1e6),
          id = 's1',
          connection = Connection(agent),
          approve = permissions.new({ ask = transcript.ask }),
        }):attach()
      end

      local function status_text(buf)
        local out = {}

        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, Document.STATUS_NAMESPACE, 0, -1, { details = true })) do
          for _, line in ipairs(mark[4].virt_lines or {}) do
            for _, chunk in ipairs(line) do
              out[#out + 1] = chunk[1]
            end
            out[#out + 1] = '\n'
          end
        end

        return table.concat(out)
      end

      it('asks under the transcript and takes the answer from 1, 2 or 3', function()
        local asked = asking_session()
        local buf = transcript.open(asked)
        local task = asked:prompt('edit it')

        vim.wait(1000, function()
          return status_text(buf):find('Allow Edit', 1, true) ~= nil
        end)

        local shown = status_text(buf)

        assert.is_truthy(shown:find('Allow Edit?', 1, true))
        assert.is_truthy(shown:find('1 Allow once', 1, true))
        assert.is_truthy(shown:find('3 Reject', 1, true))

        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_feedkeys('2', 'x', false)
        vim.wait(1000, function()
          return task.done
        end)

        local reply = agent:find(function(message)
          return message.id == 'perm-1' and message.result ~= nil
        end)

        eq('allow', reply.result.outcome.optionId)
        eq({ kind = 'permission', tool = 'Edit', allowed = true, id = 't1' }, asked.history[2])
        eq({}, transcript.asks_of(asked))
      end)

      it('lets 1, 2 and 3 be counts when nothing is being asked', function()
        transcript.open(session)

        eq('2', vim.fn.maparg('2', 'n', false, true).callback())
      end)

      it('closes the question when the turn is interrupted', function()
        local asked = asking_session()
        local buf = transcript.open(asked)

        asked:prompt('edit it')
        vim.wait(1000, function()
          return #transcript.asks_of(asked) == 1
        end)
        asked:cancel()
        vim.wait(500, function()
          return not status_text(buf):find('Allow Edit', 1, true)
        end)

        eq({}, transcript.asks_of(asked))
        assert.is_falsy(status_text(buf):find('Allow Edit', 1, true))
      end)

      it('opens the transcript in the background when a session without one asks', function()
        local asked = asking_session()

        transcript.ask({ session = asked, tool = 'Bash', params = {} })
        vim.wait(500, function()
          return transcript.buffer_of(asked) ~= nil
        end)

        assert.is_truthy(transcript.buffer_of(asked))
        assert.is_truthy(require('harness.ui.composer').winbar(asked):find('1/2/3', 1, true))
        transcript.asks_of(asked)[1].future:set_result('reject_once')
        async.drain()
      end)
    end)
  end)

  describe('foldtext', function()
    local Fold = require('core.Fold')
    local original

    before_each(function()
      original = Fold.range
      vim.cmd('enew!')
    end)

    after_each(function()
      Fold.range = original
    end)

    local function text()
      return table.concat(vim.tbl_map(function(chunk)
        return chunk[1]
      end, transcript.foldtext()))
    end

    it(
      'counts tools when a fold hides only grouped tools, and lines otherwise, closing the tree when it takes its end',
      function()
        local session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })

        session:_emit(events.prompt('look'))

        for _, id in ipairs({ 'a', 'b' }) do
          session:_emit({ kind = 'tool_call', id = id, name = 'Read', category = 'read', diffs = {} })
          session:_emit({ kind = 'tool_update', id = id, status = 'completed', output = 'x', diffs = {} })
        end

        transcript.open(session)

        local blocks = transcript.view().document.blocks
        local header

        for _, block in ipairs(blocks) do
          if block.grouped then header = block end
        end

        local last = blocks[header.index + 2]

        Fold.range = function()
          return header.finish + 1, last.finish
        end
        eq(require('harness.transcript.theme').BRANCH_END .. '⋯ 2 tools', text())

        Fold.range = function()
          return 1, 3
        end
        eq('  ⋯ 3 more lines', text())
      end
    )

    it('sums up a folded sub-agent by its tools and replies', function()
      local session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })

      session:_emit(events.prompt('delegate'))
      session:_emit({ kind = 'tool_call', id = 'A', name = 'Agent', diffs = {} })
      session:_emit({ kind = 'tool_call', id = 'r', name = 'Bash', parent = 'A', diffs = {} })
      session:_emit({ kind = 'message', text = 'found it', parent = 'A' })
      transcript.open(session)

      local blocks = transcript.view().document.blocks
      local agent

      for _, block in ipairs(blocks) do
        if block.id == 'A' then agent = block end
      end

      Fold.range = function()
        return agent.finish + 1, blocks[agent.index + 2].finish
      end
      eq(require('harness.transcript.theme').GUTTER .. '⋯ 1 tool · 1 reply', text())
    end)
  end)

  describe('vgit views', function()
    local path, session, vgit, shown, saved_show

    before_each(function()
      vim.cmd('silent! tabonly!')
      vim.cmd('enew!')
      vgit = require('harness.vgit')
      saved_show = vgit.show
      shown = nil
      vgit.show = function(files)
        shown = files
        return true
      end
      path = vim.fn.tempname() .. '.lua'
      vim.fn.writefile({ 'local z = 2' }, path)
      session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
      session:_emit(events.prompt('edit'))
      session:_emit({
        kind = 'tool_call',
        id = 't1',
        name = 'Edit',
        category = 'edit',
        status = 'completed',
        locations = { { path = path } },
        diffs = { { path = path, old = 'local y = 2', new = 'local z = 2' } },
      })
      transcript.open(session)

      for _, block in ipairs(transcript.view().document.blocks) do
        if block.kind == 'diff' then vim.api.nvim_win_set_cursor(0, { block.start + 3, 0 }) end
      end
    end)

    after_each(function()
      vgit.show = saved_show
      pcall(vim.api.nvim_del_user_command, 'VGit')
      os.remove(path)
    end)

    it('opens the edit under the cursor, as the whole file before and after', function()
      assert.is_true(transcript.show_edit())
      eq({ { filename = path, old_lines = { 'local y = 2' }, new_lines = { 'local z = 2' } } }, shown)

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      eq({ false, 'no edit here' }, { transcript.show_edit() })
    end)

    it('opens every file the session changed, from before its first edit to now', function()
      assert.is_true(transcript.show_changes(transcript.view()))
      eq({ { filename = path, old_lines = { 'local y = 2' }, new_lines = { 'local z = 2' } } }, shown)

      vim.fn.writefile({ 'local y = 2' }, path)
      eq({ false, 'this session has not changed any file' }, { transcript.show_changes(transcript.view()) })
    end)

    it('hands the file under the cursor to :VGit diff for its git diff', function()
      local ran

      vim.api.nvim_create_user_command('VGit', function(args)
        ran = args.fargs
      end, { nargs = '*' })

      assert.is_true(transcript.git_diff())
      eq({ 'diff', '--', path }, ran)
    end)

    it('says why when there is no file or no vgit', function()
      eq({ false, 'vgit is not available' }, { transcript.git_diff() })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      eq({ false, 'no file here' }, { transcript.git_diff() })
    end)

    it('yanks an edit as a patch', function()
      local text = transcript.yank()

      eq({ '--- ' .. path, '+++ ' .. path, '@@ -1 +1 @@', '-local y = 2', '+local z = 2' }, text)
    end)
  end)
end)

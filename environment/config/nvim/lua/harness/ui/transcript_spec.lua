local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local events = require('harness.events')
local fake_agent = require('harness.fake_agent')
local transcript = require('harness.ui.transcript')

local eq = assert.are.same

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

describe('harness.ui.transcript:', function()
  describe('render', function()
    it('shows prompts, replies, tool calls and the end of a turn', function()
      eq(
        {
          '# Harness',
          '',
          '> what is here?',
          '> be brief',
          '',
          'Looking',
          '',
          '`-> buffer_read`',
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
          { kind = 'thought', text = 'hidden' },
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
      assert.is_truthy(vim.tbl_contains(lines, '`-> Bash: for f in *; do echo $f done`'))
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

      assert.is_truthy(out:find('**plan**\n- [x] rename\n- [ ] test', 1, true))
      assert.is_truthy(out:find('```diff\n--- /a.lua', 1, true))
      assert.is_truthy(out:find('-local x = 1\n+local y = 1', 1, true))
      eq(1, select(2, out:gsub('```diff', '')))
      assert.is_truthy(out:find('*refused:* `Bash`', 1, true))
      eq(nil, out:find('`Read`', 1, true))
      assert.is_truthy(out:find('*failed:* `Bash`', 1, true))
      assert.is_truthy(out:find('**error:** not logged in', 1, true))
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
  end)
end)

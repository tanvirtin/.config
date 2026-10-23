local async = require('harness.async')
local commands = require('harness.ui.commands')
local fake_agent = require('harness.servers.acp.fake_agent')
local hub = require('harness.hub')
local jsonrpc = require('harness.servers.acp.jsonrpc')
local transcript = require('harness.ui.transcript')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)
local fakes

local function use_fakes(script)
  fakes = {}
  hub.config.spawn = function()
    local fake = fake_agent.new(script)
    fakes[#fakes + 1] = fake
    return fake
  end
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function settle(predicate)
  vim.wait(1000, predicate or function()
    return false
  end)
end

local function prompt_text(fake, n)
  local count = 0

  for _, message in ipairs(fake.sent) do
    if message.method == 'session/prompt' then
      count = count + 1
      if count == (n or 1) then return message.params.prompt end
    end
  end
end

describe('harness.ui.commands:', function()
  before_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
    use_fakes({
      ['session/prompt'] = function(message)
        return {
          fake_agent.chunk(message.params.sessionId, 'reply to ' .. message.params.prompt[2].text),
          jsonrpc.result(message.id, { stopReason = 'end_turn' }),
        }
      end,
    })
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
  end)

  after_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
  end)

  it('starts a session and shows its buffer in the current window', function()
    local win = vim.api.nvim_get_current_win()

    commands.run('what is here?'):wait()

    local buf = vim.api.nvim_win_get_buf(win)

    settle(function()
      return vim.tbl_contains(lines(buf), '*end_turn*')
    end)

    eq(1, #vim.api.nvim_tabpage_list_wins(0))
    assert.is_truthy(transcript.view(buf))
    eq({ '# untitled', '', '> what is here?', '', 'reply to what is here?', '', '*end_turn*', '' }, lines(buf))
  end)

  it('tells the agent where the user was, and points the tools there, behind the session buffer', function()
    local source = vim.api.nvim_get_current_buf()

    commands.run('explain', nil, { 2, 4 }):wait()

    local blocks = prompt_text(fakes[1])

    assert.is_truthy(blocks[1].text:find('(bufnr ' .. source .. ')', 1, true))
    assert.is_truthy(blocks[1].text:find('selected lines 2-4', 1, true))
    assert.is_truthy(blocks[2].text:find('Selected lines 2-4', 1, true))
    eq('explain', blocks[3].text)
    assert.is_truthy(require('nvim_mcp.tools').run('editor_state', {}):find('bufnr ' .. source .. ',', 1, true))
  end)

  it('continues the session the user was last in, from their code or from the session', function()
    local code = vim.api.nvim_get_current_buf()

    commands.run('first'):wait()

    local buf = vim.api.nvim_get_current_buf()

    vim.cmd('buffer ' .. code)
    commands.run('second'):wait()
    eq(buf, vim.api.nvim_get_current_buf())

    commands.run('third'):wait()
    settle(function()
      return #vim.tbl_filter(function(line)
        return line == '*end_turn*'
      end, lines(buf)) == 3
    end)

    local out = table.concat(lines(buf), '\n')

    assert.is_truthy(out:find('> first\n\nreply to first', 1, true))
    assert.is_truthy(out:find('> second\n\nreply to second', 1, true))
    assert.is_truthy(out:find('> third\n\nreply to third', 1, true))
    eq(1, fakes[1]:count('session/new'))

    assert.is_truthy(prompt_text(fakes[1], 3)[1].text:find('(bufnr ' .. code .. ')', 1, true))
  end)

  it('warns instead of failing when the agent cannot start', function()
    hub.config.spawn = function()
      error('claude-agent-acp: not found')
    end

    local notify = vim.notify
    local warned

    vim.notify = function(message)
      warned = message
    end

    pcall(function()
      commands.run('hi'):wait()
    end)
    settle(function()
      return warned ~= nil
    end)
    vim.notify = notify

    assert.is_truthy(warned:find('not found', 1, true))
  end)

  it('opens a session without prompting', function()
    local session = commands.new():wait()

    eq(session, transcript.view().session)
    eq(0, fakes[1]:count('session/prompt'))
  end)

  it('keeps the session when its buffer is closed, and reopens it from the selector', function()
    local session = commands.new():wait()

    vim.api.nvim_buf_delete(0, { force = true })
    async.drain()

    eq('idle', session.state)
    eq(session, hub.session(session.key))

    local picker = commands.sessions():wait()

    picker:command('query', { text = 'untitled' })
    assert.is_truthy(picker:snapshot():find('selected: ○ untitled', 1, true))
    picker:command('select')
    settle(function()
      return transcript.view() ~= nil
    end)

    eq(session, transcript.view().session)
  end)

  it('cancels the running turn of the transcript', function()
    use_fakes({
      ['session/prompt'] = function()
        return {}
      end,
    })

    local session = commands.new():wait()

    commands.run('long')
    settle(function()
      return session:running() and fakes[1]:count('session/prompt') == 1
    end)
    commands.cancel()

    eq('s1', fakes[1]:sent_method('session/cancel').params.sessionId)
  end)

  it('reports tokens per session', function()
    local session = commands.new():wait()

    require('compact').reply(session.key, string.rep('x', 400), 'short')

    local lines = commands.stats_lines()

    assert.is_truthy(lines[3]:find('| ' .. session.key .. ' |', 1, true))
    assert.is_truthy(lines[3]:find('2 tokens in 1 calls | 99 tokens |', 1, true))
  end)
end)

local agent = require('harness.agent')

local eq = assert.are.same

local function write_json(value)
  local path = vim.fn.tempname()
  local file = assert(io.open(path, 'w'))

  file:write(type(value) == 'string' and value or vim.json.encode(value))
  file:close()

  return path
end

describe('harness.agent:', function()
  after_each(function()
    agent.load(agent.PATH)
  end)

  it('has a built-in claude agent', function()
    local loaded = agent.load('/nonexistent/agents.json')

    eq('claude-agent-acp', loaded.claude.command)
    eq('claude-sonnet-5-5', loaded.claude.model)
    eq(true, loaded.claude.policy.auto_allow)
    assert.is_truthy(loaded.claude.system:find('editor-context', 1, true))
  end)

  it('loads tin\'s export over the built-ins', function()
    agent.load(write_json({
      agents = {
        claude = { command = 'my-claude', system = 'from tin' },
        gemini = { command = 'gemini', args = { '--experimental-acp' } },
      },
    }))

    eq('my-claude', agent.get('claude').command)
    eq('from tin', agent.get('claude').system)
    eq({ '--experimental-acp' }, agent.get('gemini').args)
    eq({ 'claude', 'gemini' }, agent.names())
  end)

  it('ignores an unreadable file with a warning', function()
    local notify = vim.notify
    local warned

    vim.notify = function(message)
      warned = message
    end

    local loaded = agent.load(write_json('{not json'))

    vim.notify = notify

    eq({ 'claude' }, vim.tbl_keys(loaded))
    assert.is_truthy(warned:find('unreadable', 1, true))
  end)

  it('reads $NAME env values when it spawns, not from the file', function()
    vim.env.HARNESS_SPEC_TOKEN = 'secret'

    local a = agent.Agent('x', {
      command = 'x',
      env = { TOKEN = '$HARNESS_SPEC_TOKEN', PLAIN = 'p' },
      mcp = { { name = 'm', command = 'm', args = {}, env = { { name = 'KEY', value = '$HARNESS_SPEC_TOKEN' } } } },
    })

    eq({ TOKEN = 'secret', PLAIN = 'p' }, a:environment())
    eq('secret', a:mcp_servers()[1].env[1].value)
    eq('$HARNESS_SPEC_TOKEN', a.mcp[1].env[1].value)
    eq(nil, agent.Agent('y', { command = 'y' }):environment())
  end)

  it('finds the command on PATH, else where tin installs it', function()
    eq(vim.fn.exepath('sh'), agent.Agent('sh', { command = 'sh' }):executable())
    eq(
      vim.fn.expand('~/.local/bin/not-installed-agent'),
      agent.Agent('n', { command = 'not-installed-agent' }):executable()
    )
  end)

  it('finds where an agent keeps a session\'s transcript, from its spec or its command', function()
    local dir = vim.fn.tempname()

    vim.fn.mkdir(dir .. '/project', 'p')
    vim.fn.writefile({}, dir .. '/project/abc.jsonl')

    local custom = agent.Agent('custom', { command = 'x', transcripts = dir .. '/*/{id}.jsonl' })

    eq(dir .. '/project/abc.jsonl', custom:transcript('abc'))
    eq(nil, custom:transcript('missing'))
    eq(nil, agent.Agent('other', { command = 'gemini' }):transcript('abc'))
    eq(agent.TRANSCRIPTS['claude-agent-acp'], '~/.claude/projects/*/{id}.jsonl')
    vim.fn.delete(dir, 'rf')
  end)
end)

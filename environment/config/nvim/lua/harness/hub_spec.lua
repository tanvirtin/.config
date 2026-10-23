local async = require('harness.async')
local fake_agent = require('harness.servers.acp.fake_agent')
local hub = require('harness.hub')
local jsonrpc = require('harness.servers.acp.jsonrpc')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)
local spawned

local function use_fakes(script)
  spawned = {}
  hub.config.spawn = function(a, dir)
    local fake = fake_agent.new(script)
    spawned[#spawned + 1] = { agent = a.name, dir = dir, fake = fake }
    return fake
  end
end

describe('harness.hub:', function()
  before_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
    use_fakes()
  end)

  after_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
  end)

  it('hands each session this editor as the nvim MCP server, naming the session', function()
    local session = hub.start({ dir = '/w' }):wait()
    local server = spawned[1].fake:sent_method('session/new').params.mcpServers[1]

    eq('nvim', server.name)
    eq(vim.v.progpath, server.command)
    assert.is_truthy(server.args[5]:find('nvim_mcp/run.lua', 1, true))
    eq({ { name = 'HARNESS_SESSION', value = session.key } }, server.env)
  end)

  it('keeps one workspace per directory', function()
    local a = hub.start({ dir = '/a' }):wait()
    local b = hub.start({ dir = '/b' }):wait()
    local a2 = hub.start({ dir = '/a' }):wait()

    eq(2, #spawned)
    eq({ a, a2 }, hub.sessions('/a'))
    eq({ b }, hub.sessions('/b'))
    eq({ a, b, a2 }, hub.sessions())
  end)

  it('scopes to the current tab\'s directory by default', function()
    local session = hub.start():wait()

    eq(vim.fs.normalize(vim.fn.getcwd(-1, 0)), session.dir)
  end)

  it('lets sessions start sessions, up to max_depth', function()
    hub.config.max_depth = 1

    local root = hub.start({ dir = '/w' }):wait()
    local child = hub.start({ parent = root.key }):wait()

    eq(1, child.depth)
    eq(root.key, child.parent)
    eq('/w', child.dir)

    local ok, err = pcall(function()
      return hub.start({ parent = child.key }):wait()
    end)

    eq(false, ok)
    assert.is_truthy(tostring(err):find('nest 1 deep', 1, true))
  end)

  it('refuses a turn beyond max_running', function()
    use_fakes({
      ['session/prompt'] = function()
        return {}
      end,
    })
    hub.config.max_running = 1

    local one = hub.start({ dir = '/w' }):wait()
    local two = hub.start({ dir = '/w' }):wait()

    hub.prompt(one, 'long')

    local ok, err = pcall(hub.prompt, two, 'hi')

    eq(false, ok)
    assert.is_truthy(tostring(err):find('max_running', 1, true))
    eq(1, hub.running())
  end)

  it('fires User HarnessEvent for every event', function()
    local seen = {}
    local id = vim.api.nvim_create_autocmd('User', {
      pattern = 'HarnessEvent',
      callback = function(args)
        seen[#seen + 1] = args.data.kind
      end,
    })

    local session = hub.start({ dir = '/w' }):wait()

    hub.prompt(session, 'hi'):wait()
    vim.api.nvim_del_autocmd(id)

    eq({ 'prompt', 'message', 'stop' }, seen)
  end)

  it('follows the agent\'s policy for exec tools unless configured', function()
    use_fakes({
      ['session/prompt'] = function(message, fake)
        fake.prompt_id = message.id
        return { fake_agent.permission('s1', 'mcp__nvim__lua') }
      end,
      reply = function(message, fake)
        if message.id ~= 'perm-1' then return {} end
        return { jsonrpc.result(fake.prompt_id, { stopReason = 'end_turn' }) }
      end,
    })

    local session = hub.start({ dir = '/w' }):wait()
    hub.prompt(session, 'hi'):wait()
    eq('allow', spawned[1].fake:selected())

    hub.config.auto_allow = false

    local strict = hub.start({ dir = '/other' }):wait()
    hub.prompt(strict, 'hi'):wait()
    eq('reject', spawned[2].fake:selected())
  end)

  it('reports an unknown agent', function()
    local ok, err = pcall(function()
      return hub.start({ agent = 'nope' }):wait()
    end)

    eq(false, ok)
    eq('unknown agent: nope', err)
  end)

  it('lists and loads a directory\'s stored sessions', function()
    local live = hub.start({ dir = '/w' }):wait()
    local fake = spawned[1].fake

    fake.stored = { { sessionId = 'old', cwd = '/w', title = 'yesterday' } }
    fake.histories.old = { { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'hi' } } }

    local items = hub.list('/w'):wait()

    eq({ live.id, 'old' }, { items[1].id, items[2].id })

    local loaded = hub.load({ dir = '/w', id = 'old', title = 'yesterday' }):wait()

    eq('yesterday', loaded.title)
    eq(loaded, hub.session(loaded.key))
    eq(loaded, hub.load({ dir = '/w', id = 'old' }):wait())
  end)

  it('hands over a stored session before its history arrives, holding prompts until it has', function()
    hub.start({ dir = '/w' }):wait()

    local fake = spawned[1].fake
    local seen

    fake.histories.old = { { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'hi' } } }

    local loaded = hub
      .load({
        dir = '/w',
        id = 'old',
        on_session = function(session)
          seen = { state = session.state, events = #session.history, live = hub.session(session.key) == session }
          eq('queued', hub.send(session, 'next'))
        end,
      })
      :wait()

    eq({ state = 'loading', events = 0, live = true }, seen)
    eq('idle', loaded.state)
    eq('hi', loaded.history[1].text)

    vim.wait(100, function()
      return fake:sent_method('session/prompt') ~= nil
    end)

    eq('old', fake:sent_method('session/prompt').params.sessionId)
  end)

  it('lists, loads and deletes through the configured default agent', function()
    hub.config.agent = 'opencode'

    local live = hub.start({ dir = '/w' }):wait()
    local fake = spawned[1].fake

    eq('opencode', spawned[1].agent)

    fake.stored = { { sessionId = 'old', cwd = '/w', title = 'yesterday' } }
    fake.histories.old = { { sessionUpdate = 'agent_message_chunk', content = { type = 'text', text = 'hi' } } }

    local items = hub.list('/w'):wait()

    eq({ live.id, 'old' }, { items[1].id, items[2].id })

    local loaded = hub.load({ dir = '/w', id = 'old', title = 'yesterday' }):wait()

    eq('yesterday', loaded.title)

    hub.delete({ dir = '/w', id = 'old' }):wait()

    eq('old', fake:sent_method('session/delete').params.sessionId)
  end)

  it('falls back to the exported default agent when none is configured', function()
    local agent = require('harness.agent')
    local previous = agent.default_name

    agent.default_name = 'opencode'

    hub.start({ dir = '/w' }):wait()

    agent.default_name = previous

    eq('opencode', spawned[1].agent)
  end)

  it('closes a session and forgets it', function()
    local session = hub.start({ dir = '/w' }):wait()

    hub.close(session.key)
    async.drain()

    eq(nil, hub.session(session.key))
    eq({}, hub.sessions())
    eq('closed', session.state)
  end)
end)

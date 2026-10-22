local async = require('harness.async')
local fake_agent = require('harness.fake_agent')
local hub = require('harness.hub')
local jsonrpc = require('harness.acp.jsonrpc')
local permissions = require('harness.permissions')
local tools = require('nvim_mcp.tools')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

local function run(name, args, caller)
  return tools.run(name, args or {}, caller)
end

local function settle(predicate)
  vim.wait(1000, predicate)
end

describe('harness.tools:', function()
  local fakes

  before_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
    hub.config.agent = 'claude'
    fakes = {}
    hub.config.spawn = function()
      local fake = fake_agent.new({
        ['session/prompt'] = function(message)
          return {
            fake_agent.chunk(message.params.sessionId, 'did ' .. message.params.prompt[1].text),
            jsonrpc.result(message.id, { stopReason = 'end_turn' }),
          }
        end,
      })
      fakes[#fakes + 1] = fake
      return fake
    end
    require('harness.tools').register()
    require('harness.ui.commands')
    vim.cmd('silent! tabonly!')
  end)

  after_each(function()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
  end)

  it('lists the sessions of the caller\'s directory and marks the caller', function()
    local me = hub.start({ dir = '/w' }):wait()
    local other = hub.start({ dir = '/w' }):wait()

    hub.start({ dir = '/elsewhere' }):wait()

    local listed = run('session_list', {}, me.key)

    eq({ me.key, other.key }, { listed[1].session, listed[2].session })
    eq(true, listed[1].you)
    eq(nil, listed[2].you)
    eq('claude', listed[1].agent)
  end)

  it('starts a child in the background and returns its key at once', function()
    local me = hub.start({ dir = '/w' }):wait()
    local win = vim.api.nvim_get_current_win()
    local tabs = #vim.api.nvim_list_tabpages()

    local started = run('session_new', { prompt = 'look around' }, me.key)

    eq('starting', started.state)
    eq({ session = started.session, state = 'starting' }, run('session_read', { session = started.session }, me.key))

    settle(function()
      local child = hub.session(started.session)
      return child ~= nil and child.state == 'idle' and #child.history >= 3
    end)

    local child = hub.session(started.session)

    eq(me.key, child.parent)
    eq(1, child.depth)
    eq('/w', child.dir)
    settle(function()
      return vim.fn.bufnr('harness://' .. child.key) ~= -1
    end)
    assert.is_true(vim.fn.bufnr('harness://' .. child.key) ~= -1)
    eq(tabs, #vim.api.nvim_list_tabpages())
    eq(win, vim.api.nvim_get_current_win())

    local read = run('session_read', { session = child.key }, me.key)

    eq('idle', read.state)
    assert.is_truthy(read.transcript:find('> look around\n\ndid look around', 1, true))

    local again = run('session_read', { session = child.key, since = read.next }, me.key)

    eq('', again.transcript)
  end)

  it('refuses to nest deeper than max_depth', function()
    hub.config.max_depth = 1

    local root = hub.start({ dir = '/w' }):wait()
    local child = hub.start({ parent = root.key }):wait()

    local ok, err = pcall(run, 'session_new', {}, child.key)

    eq(false, ok)
    assert.is_truthy(err:find('nest 1 deep', 1, true))
  end)

  it('reports a child that failed to start', function()
    local me = hub.start({ dir = '/w' }):wait()
    local started = run('session_new', { agent = 'nope' }, me.key)

    settle(function()
      return hub.starting(started.session) ~= true
    end)

    local ok, err = pcall(run, 'session_read', { session = started.session }, me.key)

    eq(false, ok)
    eq('session ' .. started.session .. ' failed to start: unknown agent: nope', err)
  end)

  it('prompts another idle session, but not itself or another directory\'s', function()
    local me = hub.start({ dir = '/w' }):wait()
    local other = hub.start({ dir = '/w' }):wait()
    local far = hub.start({ dir = '/elsewhere' }):wait()

    eq({ session = other.key, state = 'running' }, run('session_prompt', { session = other.key, text = 'go' }, me.key))
    settle(function()
      return not other:running()
    end)
    assert.is_truthy(run('session_read', { session = other.key }, me.key).transcript:find('did go', 1, true))

    local ok, err = pcall(run, 'session_prompt', { session = me.key, text = 'x' }, me.key)
    eq(false, ok)
    eq('a session cannot drive itself', err)

    ok, err = pcall(run, 'session_prompt', { session = far.key, text = 'x' }, me.key)
    eq(false, ok)
    assert.is_truthy(err:find('another directory', 1, true))

    ok, err = pcall(run, 'session_read', { session = 'h999' }, me.key)
    eq(false, ok)
    eq('no session h999', err)
  end)

  it('closes a session', function()
    local me = hub.start({ dir = '/w' }):wait()
    local other = hub.start({ dir = '/w' }):wait()

    eq('closed', run('session_close', { session = other.key }, me.key).state)
    eq(nil, hub.session(other.key))
  end)

  it('puts starting and prompting sessions in the exec tier', function()
    eq('exec', permissions.tier('mcp__nvim__session_new'))
    eq('exec', permissions.tier('mcp__nvim__session_prompt'))
    eq('read', permissions.tier('mcp__nvim__session_read'))
    eq('write', permissions.tier('mcp__nvim__session_close'))
  end)
end)

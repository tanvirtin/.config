local async = require('harness.async')
local fake_agent = require('harness.servers.acp.fake_agent')
local hub = require('harness.session.hub')
local jsonrpc = require('harness.servers.acp.jsonrpc')
local permissions = require('harness.permissions')
local tools = require('nvim_mcp.tools')
local acp_config = require('harness.servers.acp.config')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

local function run(name, args, caller, waited)
  return tools.run(name, args or {}, caller, waited)
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
    require('harness.ui.actions')
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

  it('clears a session\'s guides when the user prompts it, and keeps other sessions\' guides', function()
    local guides = require('ui.guides')
    local me = hub.start({ dir = '/w' }):wait()
    local other = hub.start({ dir = '/w' }):wait()
    local path = vim.fn.tempname() .. '.lua'

    vim.fn.writefile({ 'a', 'b' }, path)
    run('show', { spots = { { at = path .. ':1-2', note = 'here' } } }, me.key)
    run('show', { spots = { { at = path .. ':2', note = 'there' } } }, other.key)

    me:prompt('next')
    settle(function()
      return me.state == 'idle'
    end)

    eq(0, #guides.list(me.key))
    eq(1, #guides.list(other.key))

    run('hide', {}, me.key)
    run('hide', {}, other.key)
    vim.fn.delete(path)
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

  it('asks to be called again while a listed session is still running', function()
    local me = hub.start({ dir = '/w' }):wait()
    local busy = hub.start({ dir = '/w' }):wait()

    busy:_to('running')

    eq({ _retry_ms = 500 }, run('session_wait', { sessions = { busy.key } }, me.key, 0))
  end)

  it('returns once every listed session has settled, with each state and result', function()
    local me = hub.start({ dir = '/w' }):wait()
    local idle = hub.start({ dir = '/w' }):wait()
    local done = hub.start({ dir = '/w' }):wait()

    hub.prompt(done, 'go'):wait()

    local waited = run('session_wait', { sessions = { idle.key, done.key } }, me.key, 0)

    eq({
      { session = idle.key, state = 'idle' },
      { session = done.key, state = 'done', result = 'did go' },
    }, waited.sessions)
    eq(nil, waited.running)
    eq(nil, waited.timed_out)
  end)

  it('reports the model and cost of a settled session', function()
    local me = hub.start({ dir = '/w' }):wait()
    local done = hub.start({ dir = '/w' }):wait()

    done:configure(acp_config.options({
      {
        id = 'model',
        category = 'model',
        type = 'select',
        currentValue = 'haiku',
        options = { { value = 'haiku', name = 'Haiku' } },
      },
    }))
    done:_emit({ kind = 'usage', used = 1, size = 100, cost = 0.25 })
    hub.prompt(done, 'go'):wait()

    local waited = run('session_wait', { sessions = { done.key } }, me.key, 0)

    eq('Haiku', waited.sessions[1].model)
    eq(0.25, waited.sessions[1].cost)
  end)

  it('returns as soon as one listed session settles when until_any is set, listing the rest as running', function()
    local me = hub.start({ dir = '/w' }):wait()
    local busy = hub.start({ dir = '/w' }):wait()
    local idle = hub.start({ dir = '/w' }):wait()

    busy:_to('running')

    local waited = run('session_wait', { sessions = { busy.key, idle.key }, until_any = true }, me.key, 0)

    eq({ { session = idle.key, state = 'idle' } }, waited.sessions)
    eq({ busy.key }, waited.running)
    eq(nil, waited.timed_out)
  end)

  it('gives up at the timeout and lists the sessions still running', function()
    local me = hub.start({ dir = '/w' }):wait()
    local busy = hub.start({ dir = '/w' }):wait()

    busy:_to('running')

    local waited = run('session_wait', { sessions = { busy.key }, timeout_ms = 1000 }, me.key, 1000)

    eq(true, waited.timed_out)
    eq({ busy.key }, waited.running)
    eq({}, waited.sessions)
  end)

  it('keeps waiting on a session that is waiting on the user, and reports its ask at the timeout', function()
    local asked = {}

    hub.config.auto_allow = false
    hub.config.ask = function(request)
      asked[#asked + 1] = request
      return async.Future.new()
    end
    hub.config.spawn = function()
      local fake = fake_agent.new({
        ['session/prompt'] = function()
          return { fake_agent.permission('s1', 'Edit') }
        end,
      })
      fakes[#fakes + 1] = fake
      return fake
    end

    local asker = hub.start({ dir = '/w' }):wait()
    local me = hub.start({ dir = '/w' }):wait()

    asker:prompt('edit')
    vim.wait(1000, function()
      return #asker:waiting() == 1
    end)

    eq({ _retry_ms = 500 }, run('session_wait', { sessions = { asker.key } }, me.key, 0))

    local waited = run('session_wait', { sessions = { asker.key }, timeout_ms = 1000 }, me.key, 1000)

    eq(true, waited.timed_out)
    eq({ { session = asker.key, ask = 'Edit' } }, waited.waiting_on_user)
    eq({}, waited.sessions)
  end)

  it('refuses to wait on no sessions', function()
    local me = hub.start({ dir = '/w' }):wait()

    local ok, err = pcall(run, 'session_wait', { sessions = {} }, me.key, 0)

    eq(false, ok)
    eq('pass at least one session key', err)
  end)

  it('starts a child on the model it was asked for', function()
    local me = hub.start({ dir = '/w' }):wait()
    local started = run('session_new', { model = 'haiku' }, me.key)

    settle(function()
      return hub.session(started.session) ~= nil
    end)

    local set = fakes[1]:find(function(message)
      return message.method == 'session/set_config_option' and message.params.value == 'haiku'
    end)

    eq({ sessionId = hub.session(started.session).id, configId = 'model', value = 'haiku' }, set.params)
  end)

  it('lists each session with its model and cost', function()
    local me = hub.start({ dir = '/w' }):wait()
    local other = hub.start({ dir = '/w' }):wait()

    other:configure(acp_config.options({
      {
        id = 'model',
        category = 'model',
        type = 'select',
        currentValue = 'haiku',
        options = { { value = 'haiku', name = 'Haiku' } },
      },
    }))
    other:_emit({ kind = 'usage', used = 1, size = 100, cost = 0.5 })

    local listed = run('session_list', {}, me.key)

    eq('Haiku', listed[2].model)
    eq(0.5, listed[2].cost)
    eq(nil, listed[1].model)
    eq(nil, listed[1].cost)
  end)
end)

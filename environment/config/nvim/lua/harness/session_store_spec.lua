local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local fake_agent = require('harness.fake_agent')
local session_store = require('harness.session_store')

local eq = assert.are.same

describe('harness.session_store:', function()
  local seen, disposers

  local function session(key)
    return Session({ key = key, id = 's1', dir = '/w', connection = Connection(fake_agent.new()) }):attach()
  end

  local function record(name)
    disposers[#disposers + 1] = session_store.on(name, function(s, payload)
      seen[#seen + 1] = { name, s.key, payload and payload.kind }
    end)
  end

  before_each(function()
    session_store.clear()
    seen, disposers = {}, {}
  end)

  after_each(function()
    for _, dispose in ipairs(disposers) do
      dispose()
    end
    session_store.clear()
  end)

  it('tells listeners when a session starts, has an event, and closes', function()
    record('start')
    record('event')
    record('close')

    local s = session_store.add(session('h1'))

    s:_emit({ kind = 'message', text = 'hi' })
    session_store.remove('h1')
    s:_emit({ kind = 'message', text = 'after' })

    eq({ { 'start', 'h1' }, { 'event', 'h1', 'message' }, { 'close', 'h1' } }, seen)
    eq(nil, session_store.get('h1'))
  end)

  it('lists open sessions of a directory in key order', function()
    session_store.add(session('h2'))
    session_store.add(session('h10'))
    session_store.add(Session({ key = 'h3', id = 's3', dir = '/other', connection = Connection(fake_agent.new()) }))

    eq(
      { 'h2', 'h10' },
      vim.tbl_map(function(s)
        return s.key
      end, session_store.list('/w'))
    )
  end)

  it('fires User HarnessEvent for every session event', function()
    local data

    local id = vim.api.nvim_create_autocmd('User', {
      pattern = session_store.USER_EVENT,
      callback = function(args)
        data = args.data
      end,
    })

    session_store.add(session('h1')):_emit({ kind = 'message', text = 'hi' })
    vim.api.nvim_del_autocmd(id)

    eq({ session = 'h1', kind = 'message' }, data)
  end)

  it('keeps going when a listener fails, and stops calling a disposed one', function()
    local warned = 0
    local notify = vim.notify

    vim.notify = function()
      warned = warned + 1
    end

    disposers[#disposers + 1] = session_store.on('start', function()
      error('boom')
    end)
    record('start')

    local dispose = session_store.on('start', function()
      seen[#seen + 1] = 'disposed one'
    end)

    dispose()
    session_store.add(session('h1'))
    vim.wait(50)
    vim.notify = notify

    eq({ { 'start', 'h1' } }, seen)
    eq(1, warned)
  end)

  it('refuses events it does not have', function()
    assert.is_truthy(select(2, pcall(session_store.on, 'opened', function() end)):find('unknown store event', 1, true))
  end)
end)

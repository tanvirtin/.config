local async = require('harness.async')
local fake_agent = require('harness.fake_agent')
local hub = require('harness.hub')
local sessions = require('harness.ui.sessions')
local surfaces = require('surfaces')

local eq = assert.are.same

local defaults = vim.deepcopy(hub.config)

local function settle(predicate)
  vim.wait(1000, predicate, 10)
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('harness.ui.sessions:', function()
  local fake

  before_each(function()
    async.drain()
    hub.shutdown()
    surfaces.close_all()
    hub.config = vim.deepcopy(defaults)
    hub.config.spawn = function()
      fake = fake_agent.new()
      fake.stored = { { sessionId = 'old', cwd = '/w', title = 'Yesterday', updatedAt = '2026-10-17T09:30:00Z' } }
      return fake
    end
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
  end)

  after_each(function()
    surfaces.close_all()
    async.drain()
    hub.shutdown()
    hub.config = vim.deepcopy(defaults)
  end)

  it('lists a new-session row, then live sessions, then stored ones', function()
    local live = hub.start({ dir = '/w' }):wait()

    live.title = 'Today'

    local rows = sessions.rows(hub.list('/w'):wait())

    eq('+ New session', rows[1].label)
    eq({ '○ Today', 'idle', live.key }, { rows[2].label, rows[2].description, rows[2].key })
    eq(
      { '  Yesterday', sessions.when('2026-10-17T09:30:00Z'), 'old' },
      { rows[3].label, rows[3].description, rows[3].id }
    )
  end)

  it('says how long ago a stored session was used, in plain words', function()
    local now = 1792229400

    eq('just now', sessions.when('2026-10-17T09:30:00Z', now + 30))
    eq('5 min ago', sessions.when('2026-10-17T09:30:00Z', now + 300))
    eq('3h ago', sessions.when('2026-10-17T09:30:00Z', now + 3 * 3600))
    eq('2d ago', sessions.when('2026-10-17T09:30:00Z', now + 2 * 86400))
    eq('2026-10-17', sessions.when('2026-10-17T09:30:00Z', now + 30 * 86400))
  end)

  it('tells the user its keys', function()
    local picker = sessions.open({ dir = '/w' }):wait()
    local hints = vim.tbl_map(function(hint)
      return hint[1] .. ' ' .. hint[2]
    end, picker:hints())

    eq({ '<CR> open / new', '<C-x> delete (press twice)', '<C-n>/<C-p> move', '<Esc> close' }, hints)
  end)

  it('opens a stored session, loading it', function()
    local opened
    local picker = sessions
      .open({
        dir = '/w',
        on_open = function(session)
          opened = session
        end,
      })
      :wait()

    picker:command('query', { text = 'Yesterday' })
    picker:command('select')
    settle(function()
      return opened ~= nil
    end)

    eq('old', opened.id)
    eq('Yesterday', opened.title)
  end)

  it('starts a new session from the first row', function()
    local started = false
    local picker = sessions
      .open({
        dir = '/w',
        on_new = function()
          started = true
        end,
      })
      :wait()

    picker:command('select')
    settle(function()
      return started
    end)

    eq(true, started)
  end)

  it('deletes a session only on a second <C-x>', function()
    local picker = sessions.open({ dir = '/w' }):wait()

    picker:command('query', { text = 'Yesterday' })
    press('<C-x>')

    assert.is_truthy(picker:snapshot():find('Yesterday', 1, true))
    eq(nil, (fake:sent_method('session/delete')))

    press('<C-x>')
    settle(function()
      return fake:sent_method('session/delete') ~= nil
    end)

    eq('old', fake:sent_method('session/delete').params.sessionId)
    settle(function()
      return picker:snapshot():find('0 of 1 items', 1, true) ~= nil
    end)
    assert.is_truthy(picker:snapshot():find('query "Yesterday", 0 of 1 items', 1, true))
  end)

  it('does not delete the new-session row', function()
    local picker = sessions.open({ dir = '/w' }):wait()

    press('<C-x>')
    press('<C-x>')
    vim.wait(50, function()
      return false
    end)

    eq(nil, (fake:sent_method('session/delete')))
    assert.is_truthy(picker:snapshot():find('+ New session', 1, true))
  end)
end)

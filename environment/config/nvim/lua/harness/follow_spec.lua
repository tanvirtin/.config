local settings = require('harness.settings.follow')
local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local async = require('harness.async')
local fake_agent = require('harness.fake_agent')
local follow = require('harness.follow')

local eq = assert.are.same

describe('harness.follow:', function()
  local dir, path, session, reloads, saved, fake

  local function settle(ms)
    vim.wait(ms or (settings:get('debounce_ms') * 3))
  end

  before_each(function()
    saved = {
      debounce = settings:get('debounce_ms'),
      grace = settings:get('grace_ms'),
      poll = settings:get('poll_ms'),
      reload = follow.reload_session,
    }
    settings:set('debounce_ms', 30)
    settings:set('grace_ms', 150)
    settings:set('poll_ms', 60)
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    path = dir .. '/s1.jsonl'
    vim.fn.writefile({ '{}' }, path)
    reloads = 0
    follow.reload_session = function()
      reloads = reloads + 1
      local done = async.Future.new()
      done:set_result(true)
      return done
    end
    fake = fake_agent.new()
    session = Session({
      key = 'h1',
      id = 's1',
      dir = dir,
      connection = Connection(fake),
      agent = {
        transcript = function()
          return vim.fn.filereadable(path) == 1 and path or nil
        end,
      },
    })
  end)

  after_each(function()
    follow.stop(session)
    settings:set('debounce_ms', saved.debounce)
    settings:set('grace_ms', saved.grace)
    settings:set('poll_ms', saved.poll)
    follow.reload_session = saved.reload
    vim.fn.delete(dir, 'rf')
  end)

  it('reloads when another program writes the transcript, and marks the session as driven elsewhere', function()
    local notified

    session:subscribe(function(event)
      if event.kind == 'external' then notified = true end
    end)
    follow.start(session)
    eq('file', follow.source(session))

    vim.fn.writefile({ '{}', '{"turn":2}' }, path)
    vim.wait(1000, function()
      return reloads > 0
    end)

    eq(1, reloads)
    eq(true, notified)
    assert.is_truthy(session.external)
  end)

  it('coalesces a burst of writes into one reload', function()
    follow.start(session)

    for i = 1, 5 do
      vim.fn.writefile({ '{}', tostring(i) }, path)
    end
    settle(400)

    eq(1, reloads)
  end)

  it('keeps following a transcript replaced by rename', function()
    follow.start(session)

    for i = 1, 2 do
      vim.fn.writefile({ 'v' .. i }, path .. '.tmp')
      vim.uv.fs_rename(path .. '.tmp', path)
      vim.wait(1000, function()
        return reloads == i
      end)
    end

    eq(2, reloads)
  end)

  it('treats writes made while its own turn runs, or just after, as its own', function()
    follow.start(session)
    session.state = 'running'
    vim.fn.writefile({ '{}', 'mine' }, path)
    settle()
    session.state = 'idle'
    session.turn_ended = vim.uv.now()
    settle(settings:get('grace_ms') * 3)

    eq(0, reloads)

    vim.fn.writefile({ '{}', 'mine', 'theirs' }, path)
    vim.wait(1000, function()
      return reloads > 0
    end)

    eq(1, reloads)
  end)

  it('stops cleanly, leaving nothing that can reload', function()
    follow.start(session)
    follow.stop(session)

    vim.fn.writefile({ 'after stop' }, path)
    settle()

    eq(false, follow.is_following(session))
    eq(0, reloads)
  end)

  it('polls the session list when it cannot find a transcript, and picks the file up once it appears', function()
    vim.fn.delete(path)
    fake.stored = { { sessionId = 's1', cwd = dir, updatedAt = 't1' } }
    session.connection.agent_capabilities = { sessionCapabilities = { list = {} } }

    local transcript = require('harness.ui.transcript')
    local visible = transcript.buffer_of

    transcript.buffer_of = function()
      return vim.api.nvim_get_current_buf()
    end

    follow.start(session)
    eq('poll', follow.source(session))

    settle(settings:get('poll_ms') * 3)
    fake.stored[1].updatedAt = 't2'
    vim.wait(1000, function()
      return reloads > 0
    end)

    eq(1, reloads)

    vim.fn.writefile({ '{}' }, path)
    vim.wait(1000, function()
      return follow.source(session) == 'file'
    end)
    transcript.buffer_of = visible

    eq('file', follow.source(session))
  end)
end)

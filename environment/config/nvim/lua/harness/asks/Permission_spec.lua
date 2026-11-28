local Connection = require('harness.servers.acp.Connection')
local Session = require('harness.session.Session')
local fake_agent = require('harness.servers.acp.fake_agent')
local asks = require('harness.asks')
local Permission = require('harness.asks.Permission')

local eq = assert.are.same

describe('harness.asks.Permission:', function()
  local session

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
  end)

  it('queues asks per session and answers the oldest first', function()
    local first = Permission.ask({ session = session, tool = 'Bash', input = { command = 'ls' } })
    local second = Permission.ask({ session = session, tool = 'Edit' })

    eq(2, #asks.asks_of(session))
    assert.is_true(asks.answer(session, Connection.DECISION.allow_once))
    eq(Connection.DECISION.allow_once, first.result.kind)
    eq(
      { second },
      vim.tbl_map(function(ask)
        return ask.future
      end, asks.asks_of(session))
    )
  end)

  it('answers nothing when nothing is asked', function()
    assert.is_false(asks.answer(session, Connection.DECISION.allow_once))
  end)

  it('dismisses an ask as cancelled', function()
    local future = Permission.ask({ session = session, tool = 'Bash' })

    future.dismiss()

    eq(Connection.DECISION.cancelled, future.result.kind)
    eq(0, #asks.asks_of(session))
  end)

  it('forgets a settled ask instead of retaining it', function()
    local future = Permission.ask({ session = session, tool = 'Bash' })

    assert.is_true(asks.answer(session, Connection.DECISION.allow_once))
    eq(Connection.DECISION.allow_once, future.result.kind)

    local _, open

    for i = 1, 10 do
      local name, value = debug.getupvalue(asks.asks_of, i)

      if name == 'open' then
        open = value
        break
      end
    end

    eq(nil, open[session])
  end)

  it('opens the transcript in the background so the ask has somewhere to show', function()
    Permission.ask({ session = session, tool = 'Bash' })

    vim.wait(500, function()
      return require('harness.ui.display').buffer_of(session) ~= nil
    end)

    assert.truthy(require('harness.ui.display').buffer_of(session))
    eq(1, #vim.api.nvim_tabpage_list_wins(0))
  end)

  local function labels(choices)
    return vim.tbl_map(function(choice)
      return choice.label
    end, choices)
  end

  it('relabels the always choice to cover the whole fleet for a sub-agent', function()
    local choices = Permission.choices_for({ tool = 'mcp__nvim__lua', session = { parent = 'h1' } })

    eq({ 'Allow once', Permission.FLEET_ALWAYS, 'Reject' }, labels(choices))
  end)

  it('keeps the usual always label for a session without a parent', function()
    local choices = Permission.choices_for({ tool = 'mcp__nvim__lua', session = {} })

    eq({ 'Allow once', 'Allow always (this session)', 'Reject' }, labels(choices))
  end)

  it('keeps an always choice the agent provided with its own option and label', function()
    local choices = Permission.choices_for({
      tool = 'mcp__nvim__lua',
      session = { parent = 'h1' },
      choices = { { kind = 'allow_always', label = 'Always here', option = 'all' } },
    })

    eq({ 'Always here' }, labels(choices))
    eq('all', choices[1].option)
  end)
end)

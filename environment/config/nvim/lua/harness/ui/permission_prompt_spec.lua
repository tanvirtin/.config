local Connection = require('harness.servers.acp.connection')
local Session = require('harness.session')
local fake_agent = require('harness.servers.acp.fake_agent')
local permission_prompt = require('harness.ui.permission_prompt')

local eq = assert.are.same

describe('harness.ui.permission_prompt:', function()
  local session

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
  end)

  it('queues asks per session and answers the oldest first', function()
    local first = permission_prompt.ask({ session = session, tool = 'Bash', input = { command = 'ls' } })
    local second = permission_prompt.ask({ session = session, tool = 'Edit' })

    eq(2, #permission_prompt.asks_of(session))
    assert.is_true(permission_prompt.answer(session, Connection.DECISION.allow_once))
    eq(Connection.DECISION.allow_once, first.result)
    eq(
      { second },
      vim.tbl_map(function(ask)
        return ask.future
      end, permission_prompt.asks_of(session))
    )
  end)

  it('answers nothing when nothing is asked', function()
    assert.is_false(permission_prompt.answer(session, Connection.DECISION.allow_once))
  end)

  it('dismisses an ask as cancelled', function()
    local future = permission_prompt.ask({ session = session, tool = 'Bash' })

    future.dismiss()

    eq(Connection.DECISION.cancelled, future.result)
    eq(0, #permission_prompt.asks_of(session))
  end)

  it('opens the transcript in the background so the ask has somewhere to show', function()
    permission_prompt.ask({ session = session, tool = 'Bash' })

    vim.wait(500, function()
      return require('harness.ui.display').buffer_of(session) ~= nil
    end)

    assert.truthy(require('harness.ui.display').buffer_of(session))
    eq(1, #vim.api.nvim_tabpage_list_wins(0))
  end)
end)

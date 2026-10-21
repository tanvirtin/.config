local Connection = require('harness.acp.connection')
local Session = require('harness.session')
local display = require('harness.ui.display')
local fake_agent = require('harness.fake_agent')

local eq = assert.are.same

describe('harness.ui.display:', function()
  local session

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    session = Session({ key = 'h' .. math.random(1e6), id = 's1', connection = Connection(fake_agent.new()) })
  end)

  it('keeps one view per session, found by session or buffer', function()
    local buf = display.open(session)

    eq(buf, display.open(session))
    eq(buf, display.buffer_of(session))
    eq(display.view(buf), display.view_of(session))
    eq(vim.api.nvim_get_current_win(), display.window())
  end)

  it('opens in the background without touching any window', function()
    local win = vim.api.nvim_get_current_win()
    local before = vim.api.nvim_win_get_buf(win)
    local buf = display.open(session, { background = true })

    eq(before, vim.api.nvim_win_get_buf(win))
    eq(0, #vim.fn.win_findbuf(buf))
  end)

  it('reveals a hidden transcript in a new split at the top, and leaves a shown one alone', function()
    vim.cmd('enew')

    local source = { win = vim.api.nvim_get_current_win(), buf = vim.api.nvim_get_current_buf() }
    local shown = display.reveal(session, nil, source)

    eq(2, #vim.api.nvim_tabpage_list_wins(0))
    eq(display.buffer_of(session), vim.api.nvim_win_get_buf(shown))
    eq(source.buf, display.view_of(session).source_buf)
    assert.is_nil(display.reveal(session, nil, source))
  end)

  it('forgets a session by wiping its buffer', function()
    local buf = display.open(session)

    display.forget(session)

    eq(false, vim.api.nvim_buf_is_valid(buf))
    assert.is_nil(display.view_of(session))
  end)
end)

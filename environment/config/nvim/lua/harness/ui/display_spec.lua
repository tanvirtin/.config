local Connection = require('harness.servers.acp.Connection')
local Session = require('harness.Session')
local display = require('harness.ui.display')
local fake_agent = require('harness.servers.acp.fake_agent')

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

  it('reveals a hidden transcript in a new split at the top, and lands a shown one where it is', function()
    vim.cmd('enew')

    local source = { win = vim.api.nvim_get_current_win(), buf = vim.api.nvim_get_current_buf() }
    local shown = display.reveal(session, nil, source)

    eq(2, #vim.api.nvim_tabpage_list_wins(0))
    eq(display.buffer_of(session), vim.api.nvim_win_get_buf(shown))
    eq(source.buf, display.view_of(session).source_buf)
    eq(shown, display.reveal(session, nil, source))
    eq(2, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it('takes a shown transcript that was scrolled up back to its end when revealed again', function()
    local events = require('harness.types.events')

    for i = 1, 60 do
      session:_emit(events.prompt('turn ' .. i))
    end

    local buf = display.open(session)
    local view = display.view(buf)
    local win = vim.api.nvim_get_current_win()

    eq(vim.api.nvim_buf_line_count(buf), vim.api.nvim_win_get_cursor(win)[1])

    vim.cmd('normal! gg')
    view.following:observe_all(view:windows())

    eq(1, vim.fn.line('w0', win))

    display.reveal(session, win, { win = win, buf = buf })

    eq(vim.api.nvim_buf_line_count(buf), vim.api.nvim_win_get_cursor(win)[1])
    assert.is_true(vim.fn.line('w$', win) >= vim.api.nvim_buf_line_count(buf))
  end)

  it('keeps a current session per tab, never one from another tab', function()
    local other = Session({ key = 'h' .. math.random(1e6), id = 's2', connection = Connection(fake_agent.new()) })

    display.open(session)
    vim.cmd('enew')

    eq(session, display.last().session)

    vim.cmd('tabnew')
    assert.is_nil(display.last())

    display.open(other)
    vim.cmd('enew')
    eq(other, display.last().session)

    vim.cmd('tabprevious')
    eq(session, display.last().session)
  end)

  it('falls back to a transcript shown in the tab when none was entered there', function()
    vim.cmd('tabnew')

    local buf = display.open(session, { background = true })

    vim.cmd('vsplit')
    vim.api.nvim_win_set_buf(0, buf)
    vim.cmd('wincmd p')

    eq(session, display.last().session)
  end)

  describe('the session a selection goes to', function()
    local function second()
      return Session({ key = 'h' .. math.random(1e6), id = 's2', connection = Connection(fake_agent.new()) })
    end

    it('is the current one when it is in sight', function()
      local other = second()

      display.open(session)
      vim.cmd('vsplit')
      display.open(other)

      local view, choices = display.target()

      eq(other, view.session)
      assert.is_nil(choices)
    end)

    it('is the only transcript in sight when the current one is hidden', function()
      local other = second()

      display.open(other)
      vim.cmd('enew')
      display.open(session)
      vim.cmd('vsplit')
      vim.cmd('enew')
      display.set_current(display.view_of(other))

      local view, choices = display.target()

      eq(session, view.session)
      assert.is_nil(choices)
    end)

    it('asks when the current one is hidden and several others are in sight', function()
      local other, third = second(), second()

      display.open(session)
      vim.cmd('vsplit')
      display.open(other)
      vim.cmd('vsplit')
      display.open(third, { background = true })
      display.set_current(display.view_of(third))

      local view, choices = display.target()

      assert.is_nil(view)
      eq(2, #choices)
    end)

    it('is nothing when no transcript was ever opened in the tab', function()
      vim.cmd('tabnew')

      local view, choices = display.target()

      assert.is_nil(view)
      assert.is_nil(choices)
    end)

    it('marks the current one only while several are in sight', function()
      local other = second()
      local first_win = vim.api.nvim_get_current_win()
      local Window = require('core.Window')

      display.open(session)
      eq(false, display.is_target(display.view_of(session), Window(first_win)))

      vim.cmd('vsplit')

      local other_win = vim.api.nvim_get_current_win()

      display.open(other)

      eq(true, display.is_target(display.view_of(other), Window(other_win)))
      eq(false, display.is_target(display.view_of(session), Window(first_win)))
      assert.is_truthy(vim.wo[other_win].winbar:find('selections go here', 1, true))

      display.set_current(display.view_of(session))
      assert.is_nil(vim.wo[other_win].winbar:find('selections go here', 1, true))
      assert.is_truthy(vim.wo[first_win].winbar:find('selections go here', 1, true))
    end)
  end)

  it('forgets a session by wiping its buffer', function()
    local buf = display.open(session)

    display.forget(session)

    eq(false, vim.api.nvim_buf_is_valid(buf))
    assert.is_nil(display.view_of(session))
  end)
end)

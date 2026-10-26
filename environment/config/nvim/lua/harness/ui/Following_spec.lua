local Window = require('core.Window')
local Following = require('harness.ui.Following')
local sticky_bottom = require('harness.ui.sticky_bottom')

local eq = assert.are.same

describe('harness.ui.Following:', function()
  local win, bufnr, reserve, following
  local cmdheight = vim.o.cmdheight

  -- shrinking the only window gives its rows to the command line
  after_each(function()
    vim.o.cmdheight = cmdheight
  end)

  local function window()
    return Window(win)
  end

  local function append(count)
    local lines = {}

    for i = 1, count do
      lines[i] = 'more ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
  end

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    win = vim.api.nvim_get_current_win()
    bufnr = vim.api.nvim_get_current_buf()
    vim.wo[win].wrap = false
    reserve = 4
    following = Following(function()
      return reserve
    end)

    local lines = {}

    for i = 1, 200 do
      lines[i] = 'line ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end)

  it('lands on the end with the reserved rows free, decorating in between', function()
    local decorated = false

    following:land(window(), function()
      decorated = true
    end)

    eq(true, decorated)
    eq(200, vim.api.nvim_win_get_cursor(win)[1])
    eq(reserve, sticky_bottom.room(window()))
  end)

  it('follows a window whose end is in view, and one whose rows grew without it scrolling', function()
    following:land(window(), function() end)
    eq(true, following:follows(window()))

    append(20)
    eq(false, sticky_bottom.at_end(window()))
    eq(true, following:follows(window()))
  end)

  it('stops following once the window scrolls away from the end', function()
    following:land(window(), function() end)
    vim.cmd('normal! gg')
    following:track({ window() })
    append(1)
    eq(false, following:follows(window()))
  end)

  it('stops following as soon as the window is scrolled up, before the end leaves view', function()
    following:land(window(), function() end)
    vim.cmd('normal! 3\25')
    following:track({ window() })

    local top = vim.fn.line('w0', win)

    eq(true, sticky_bottom.at_end(window()))
    eq(false, following:follows(window()))

    append(2)
    following:keep_end({ window() })

    eq(top, vim.fn.line('w0', win))
  end)

  it('follows again once the window is scrolled back down to the edge', function()
    following:land(window(), function() end)
    vim.cmd('normal! gg')
    following:track({ window() })
    eq(false, following:follows(window()))

    vim.cmd('normal! G')
    vim.cmd('normal! ' .. (reserve + 1) .. '\5')
    following:track({ window() })

    eq(true, following:follows(window()))
  end)

  it('stops following when the window is scrolled with the cursor on the last row', function()
    reserve = 0
    following:land(window(), function() end)
    following:track({ window() })

    -- the cursor sits on the bottom row, where a scroll carries it along
    eq(vim.api.nvim_win_get_height(win), vim.fn.winline())

    local top = vim.fn.line('w0', win)

    vim.cmd('normal! 3\25')
    following:track({ window() })

    assert.is_true(vim.fn.line('w0', win) < top)
    eq(false, following:follows(window()))
  end)

  it('keeps following when rows above the window go away', function()
    following:land(window(), function() end)
    following:track({ window() })

    local top = vim.fn.line('w0', win)

    vim.api.nvim_buf_set_lines(bufnr, 0, 20, false, {})
    following:track({ window() })

    assert.is_true(vim.fn.line('w0', win) < top)
    eq(true, following:follows(window()))
  end)

  it('keeps following when a stream drops rows above the window and adds rows below', function()
    following:land(window(), function() end)
    following:track({ window() })

    local top = vim.fn.line('w0', win)

    vim.api.nvim_buf_set_lines(bufnr, 0, 3, false, {})
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'later', 'later' })
    following:track({ window() })

    assert.is_true(vim.fn.line('w0', win) < top)
    eq(true, following:follows(window()))
  end)

  it('glides the newest line onto the edge of the reserved rows', function()
    following:land(window(), function() end)
    append(3)
    following:glide(window(), true)
    eq(reserve, sticky_bottom.room(window()))
    eq(203, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it('gives back rows when the reserve shrinks, but not when it drops to nothing', function()
    following:land(window(), function() end)
    reserve = 2
    following:glide(window(), false)
    eq(2, sticky_bottom.room(window()))

    reserve = 0
    following:glide(window(), false)
    eq(2, sticky_bottom.room(window()))
  end)

  it('asks to land a window it has not settled yet, and one left at the end', function()
    eq(true, following:arrive(window()))

    following:land(window(), function() end)
    eq(true, following:arrive(window()))

    vim.cmd('normal! gg')
    following:track({ window() })
    eq(false, following:arrive(window()))
  end)

  it('does not land a window that was scrolled up since it was last seen', function()
    following:land(window(), function() end)
    vim.cmd('normal! 6\25')
    following:track({ window() })

    eq(false, following:arrive(window()))
  end)

  it('keeps a scrolled window where it is when the composer takes its rows', function()
    following:land(window(), function() end)
    vim.cmd('normal! 6\25')
    following:track({ window() })

    local top = vim.fn.line('w0', win)

    -- a shrinking window drags the cursor's line, parked on the bottom row, into view
    vim.api.nvim_win_set_height(win, vim.api.nvim_win_get_height(win) - 6)
    assert.is_true(vim.fn.line('w0', win) > top)
    following:hold_end({ window() })

    local cursor = vim.api.nvim_win_get_cursor(win)[1]

    eq(top, vim.fn.line('w0', win))
    assert.is_true(cursor >= top and cursor <= vim.fn.line('w$', win))
    eq(false, following:follows(window()))
  end)

  it('stops following when a scroll only reveals the rows drawn above the top line', function()
    following:land(window(), function() end)

    local top = vim.fn.line('w0', win)
    local ns = vim.api.nvim_create_namespace('harness.ui.Following_spec')

    vim.api.nvim_buf_set_extmark(bufnr, ns, top - 1, 0, { virt_lines = { { { 'rule' } } }, virt_lines_above = true })
    following:settle(window())

    vim.cmd('normal! 1\25')
    eq(top, vim.fn.line('w0', win))
    eq(1, vim.fn.winsaveview().topfill)

    following:hold_end({ window() })

    eq(false, following:follows(window()))
    eq(top, vim.fn.line('w0', win))
    eq(1, vim.fn.winsaveview().topfill)
  end)

  it('keeps a scroll made in the same moment the window is resized', function()
    following:land(window(), function() end)
    following:track({ window() })

    local edge = vim.fn.line('w0', win)

    vim.cmd('normal! 20\25')
    vim.api.nvim_win_set_height(win, vim.api.nvim_win_get_height(win) - 1)

    -- the shrink shifts the view a little to keep the cursor in it, but never back to the end
    local top = vim.fn.line('w0', win)

    following:hold_end({ window() })

    eq(top, vim.fn.line('w0', win))
    assert.is_true(top < edge)
    eq(false, following:follows(window()))
  end)

  it('never moves a window that nothing moved', function()
    following:land(window(), function() end)

    local view = vim.fn.winsaveview()

    for _ = 1, 3 do
      following:hold_end({ window() })
    end

    eq(view, vim.fn.winsaveview())
    eq(true, following:follows(window()))
  end)

  it('keeps a settled top line through a resize made under the window', function()
    following:land(window(), function() end)
    following:track({ window() })

    local top = following:of(window()).top

    vim.api.nvim_win_set_height(win, vim.api.nvim_win_get_height(win) - 6)
    following:track({ window() })

    eq(top, following:of(window()).top)
    eq(true, following:follows(window()))
  end)

  it('forgets a closed window and its mark', function()
    following:land(window(), function() end)

    local state = following:of(window())

    following:forget(win)

    assert.is_nil(following.windows[win])
    assert.is_nil(state.buffer:get_extmark_row(Following.ANCHOR, state.anchor))
  end)
end)

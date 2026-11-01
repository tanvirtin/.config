local Window = require('core.Window')
local Following = require('harness.ui.Following')
local sticky_bottom = require('harness.ui.sticky_bottom')

local eq = assert.are.same

describe('harness.ui.Following:', function()
  local win, bufnr, reserve, following
  local cmdheight = vim.o.cmdheight

  after_each(function()
    vim.o.cmdheight = cmdheight
  end)

  local function window()
    return Window(win)
  end

  local function top()
    return vim.fn.line('w0', win)
  end

  local function cursor()
    return vim.api.nvim_win_get_cursor(win)
  end

  local function append(count)
    local lines = {}

    for i = 1, count do
      lines[i] = 'more ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
  end

  local function rewrite_tail(from, count)
    local lines = {}

    for i = 1, count do
      lines[i] = 'rewritten ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, from, -1, false, lines)
  end

  local function land()
    following:land(window(), function() end)
  end

  -- the reader moved, or the window was resized: read the view, then apply it
  local function settle()
    if not following:resized(window()) then following:observe(window()) end

    following:sync(window())
  end

  -- the stream rewrote the buffer: only put the view back, and record it
  local function redraw()
    following:sync(window())
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
    eq(200, cursor()[1])
    eq(reserve, sticky_bottom.room(window()))
    eq(true, following:follows(window()))
  end)

  it('follows a window whose end is in view, and one whose rows grew without it scrolling', function()
    land()
    eq(true, following:follows(window()))

    append(20)
    eq(false, sticky_bottom.at_end(window()))

    redraw()
    eq(true, following:follows(window()))
    assert.is_true(sticky_bottom.at_end(window()))
  end)

  it('stops following once the window scrolls away from the end', function()
    land()
    vim.cmd('normal! gg')
    settle()
    eq(false, following:follows(window()))

    local before = top()

    append(1)
    settle()

    eq(before, top())
  end)

  it('stops following as soon as the window is scrolled up, before the end leaves view', function()
    land()
    vim.cmd('normal! 3\25')
    settle()

    local before = top()

    eq(true, sticky_bottom.at_end(window()))
    eq(false, following:follows(window()))

    append(2)
    settle()

    eq(before, top())
  end)

  it('follows again once the window is scrolled back down to the edge', function()
    land()
    vim.cmd('normal! gg')
    settle()
    eq(false, following:follows(window()))

    vim.cmd('normal! G')
    vim.cmd('normal! ' .. (reserve + 1) .. '\5')
    settle()

    eq(true, following:follows(window()))
  end)

  it('follows again when scrolled back down to the bottom, short of the reserved edge', function()
    land()
    vim.cmd('normal! gg')
    settle()
    eq(false, following:follows(window()))

    append(1)
    vim.cmd('normal! G')
    settle()

    eq(true, sticky_bottom.at_end(window()))
    eq(true, following:follows(window()))
  end)

  it('follows the end when a rewrite swallows the row the reader was on', function()
    land()
    vim.cmd('normal! 100G')
    settle()
    eq(false, following:follows(window()))

    -- the rewrite ends the buffer above the row the reader was on
    rewrite_tail(50, 20)
    redraw()

    eq(true, following:follows(window()))
    assert.is_true(sticky_bottom.at_end(window()))
  end)

  it('keeps following when a rewrite leaves the edge past the last line', function()
    land()
    redraw()

    local edge = top()

    rewrite_tail(edge - 20, 60)
    redraw()

    eq(true, following:follows(window()))
    assert.is_true(sticky_bottom.at_end(window()))
  end)

  it('follows again when a shrinking tail brought the end back into view, after scrolling down', function()
    land()
    vim.cmd('normal! 5\25')
    settle()
    eq(false, sticky_bottom.at_end(window()))
    eq(false, following:follows(window()))

    -- the stream rewrites the tail shorter below the reader: the anchor
    -- survives, but the end comes back into view
    vim.api.nvim_buf_set_lines(bufnr, -3, -1, false, {})
    redraw()

    eq(true, sticky_bottom.at_end(window()))
    eq(false, following:follows(window()))

    vim.cmd('normal! 1\5')
    settle()

    eq(true, following:follows(window()))
  end)

  it('stops following when the window is scrolled with the cursor on the last row', function()
    reserve = 0
    land()
    redraw()

    eq(vim.api.nvim_win_get_height(win), vim.fn.winline())

    local before = top()

    vim.cmd('normal! 3\25')
    settle()

    assert.is_true(top() < before)
    eq(false, following:follows(window()))
  end)

  it('keeps following when rows above the window go away', function()
    land()
    redraw()

    local before = top()

    vim.api.nvim_buf_set_lines(bufnr, 0, 20, false, {})
    redraw()

    assert.is_true(top() < before)
    eq(true, following:follows(window()))
    assert.is_true(sticky_bottom.at_end(window()))
  end)

  it('keeps following when a stream drops rows above the window and adds rows below', function()
    land()
    redraw()

    local before = top()

    vim.api.nvim_buf_set_lines(bufnr, 0, 3, false, {})
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'later', 'later' })
    redraw()

    assert.is_true(top() < before)
    eq(true, following:follows(window()))
  end)

  it('glides the newest line onto the edge of the reserved rows', function()
    land()
    append(3)
    following:sync(window(), { with_cursor = true })

    eq(reserve, sticky_bottom.room(window()))
    eq(203, cursor()[1])
  end)

  it('keeps at least the reserved rows free as the reserve grows, and leaves the text alone as it shrinks', function()
    land()

    reserve = 6
    following:sync(window())
    eq(6, sticky_bottom.room(window()))

    reserve = 2
    following:sync(window())
    eq(6, sticky_bottom.room(window()))
  end)

  it('settles a window it has not seen yet', function()
    eq(false, following:settled(window()))

    land()
    eq(true, following:settled(window()))
    eq(true, following:follows(window()))

    vim.cmd('normal! gg')
    settle()
    eq(false, following:follows(window()))
  end)

  it('does not land a window scrolled up since it was last seen', function()
    land()
    vim.cmd('normal! 6\25')
    settle()

    eq(true, following:holds(window()))

    local before = top()

    following:sync(window())
    eq(before, top())
  end)

  it('keeps a scrolled window where it is when the composer takes its rows', function()
    land()
    vim.cmd('normal! 6\25')
    settle()

    local before = top()

    -- a shrinking window drags the cursor's line, parked on the bottom row, into view
    vim.api.nvim_win_set_height(win, vim.api.nvim_win_get_height(win) - 6)
    settle()

    local line = cursor()[1]

    eq(before, top())
    assert.is_true(line >= top() and line <= vim.fn.line('w$', win))
    eq(false, following:follows(window()))
  end)

  it('stops following when a scroll only reveals the rows drawn above the top line', function()
    land()

    local before = top()
    local ns = vim.api.nvim_create_namespace('harness.ui.Following_spec')

    vim.api.nvim_buf_set_extmark(bufnr, ns, before - 1, 0, {
      virt_lines = { { { 'rule' } } },
      virt_lines_above = true,
    })
    redraw()

    vim.cmd('normal! 1\25')
    settle()

    eq(false, following:follows(window()))
    assert.is_true(top() <= before)
  end)

  it('keeps a scroll made in the same moment the window is resized', function()
    land()
    redraw()

    local edge = top()

    vim.cmd('normal! 20\25')
    settle()

    local scrolled = top()

    vim.api.nvim_win_set_height(win, vim.api.nvim_win_get_height(win) - 1)
    settle()

    eq(scrolled, top())
    assert.is_true(scrolled < edge)
    eq(false, following:follows(window()))
  end)

  it('keeps a scroll down made in the same moment the window is resized', function()
    land()
    vim.cmd('normal! 40\25')
    settle()
    eq(false, following:follows(window()))

    vim.cmd('normal! 5\5')
    settle()

    local scrolled = top()

    vim.api.nvim_win_set_height(win, vim.api.nvim_win_get_height(win) - 1)
    settle()

    eq(scrolled, top())
  end)

  it('keeps following when the window is narrowed and the text reflows', function()
    vim.wo[win].wrap = true
    land()
    redraw()
    eq(true, following:follows(window()))

    vim.api.nvim_win_set_width(win, vim.api.nvim_win_get_width(win) - 20)
    settle()

    eq(true, following:follows(window()))
    assert.is_true(sticky_bottom.at_end(window()))
  end)

  it('starts clean when the window comes to show another buffer', function()
    land()
    eq(true, following:settled(window()))

    local other = vim.api.nvim_create_buf(true, false)

    vim.api.nvim_buf_set_lines(other, 0, -1, false, { 'a', 'b', 'c' })
    vim.api.nvim_win_set_buf(win, other)

    eq(false, following:settled(window()))
    eq(nil, following:of(window()).mode)

    vim.api.nvim_buf_delete(other, { force = true })
  end)

  describe('over folded rows', function()
    before_each(function()
      vim.wo[win].foldmethod = 'manual'
      vim.wo[win].foldenable = true
      vim.cmd('184,192fold')
    end)

    it('keeps following when the window grows and the top line jumps across a closed fold', function()
      vim.api.nvim_win_set_height(win, 11)
      land()
      redraw()
      eq(true, following:follows(window()))

      vim.api.nvim_win_set_height(win, 22)
      settle()

      eq(true, following:follows(window()))
      eq(true, sticky_bottom.at_end(window()))
    end)

    it('keeps following when the window shrinks and the top line jumps across a closed fold', function()
      vim.api.nvim_win_set_height(win, 22)
      land()
      redraw()
      vim.api.nvim_win_set_height(win, 11)
      settle()

      eq(true, following:follows(window()))
      eq(true, sticky_bottom.at_end(window()))
    end)

    it('still stops following when the reader scrolls up across the fold as the window grows', function()
      vim.api.nvim_win_set_height(win, 11)
      land()
      redraw()
      vim.cmd('normal! 30\25')
      settle()
      vim.api.nvim_win_set_height(win, 22)
      settle()

      eq(false, following:follows(window()))
    end)
  end)

  it('never moves a window that nothing moved', function()
    land()

    local view = vim.fn.winsaveview()

    for _ = 1, 3 do
      settle()
    end

    eq(view, vim.fn.winsaveview())
    eq(true, following:follows(window()))
  end)

  it('forgets a closed window and its mark', function()
    land()
    vim.cmd('normal! 6\25')
    settle()

    local state = following:of(window())

    assert.is_not_nil(state.anchor)

    following:forget(win)

    assert.is_nil(following.windows[win])
    assert.is_nil(state.buffer:get_extmark_row(Following.ANCHOR, state.anchor))
  end)

  -- a subagent writes under its tool call, in the middle of the transcript
  local function insert_at(row, count)
    local lines = {}

    for i = 1, count do
      lines[i] = 'child ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)
  end

  local function top_text()
    return vim.api.nvim_buf_get_lines(bufnr, top() - 1, top(), false)[1]
  end

  it('holds the reader\'s row when a subagent writes above it', function()
    land()
    vim.cmd('normal! 100G')
    vim.cmd('normal! zt')
    settle()
    eq(true, following:holds(window()))

    local before = top_text()

    insert_at(20, 15)
    redraw()

    eq(before, top_text())
    eq(true, following:holds(window()))
  end)

  it('holds the reader\'s row when a subagent writes on screen below it', function()
    land()
    vim.cmd('normal! 100G')
    vim.cmd('normal! zt')
    settle()

    local before = top()

    insert_at(before + 2, 5)
    redraw()

    eq(before, top())
    eq(true, following:holds(window()))
  end)

  it('keeps following the end while subagents write in the middle', function()
    land()
    redraw()

    for _ = 1, 5 do
      insert_at(50, 3)
      insert_at(80, 2)
      redraw()
    end

    eq(true, following:follows(window()))
    assert.is_true(sticky_bottom.at_end(window()))
    assert.is_true(sticky_bottom.room(window()) >= reserve)
  end)

  it('keeps the edge clear of status rows drawn under the last line', function()
    land()
    redraw()

    local ns = vim.api.nvim_create_namespace('harness.following.spec.status')

    vim.api.nvim_buf_set_extmark(bufnr, ns, vim.api.nvim_buf_line_count(bufnr) - 1, 0, {
      virt_lines = { { { '' } }, { { 'working' } } },
    })
    redraw()

    eq(true, following:follows(window()))
    assert.is_true(sticky_bottom.room(window()) >= reserve)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end)
end)

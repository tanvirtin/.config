local Window = require('core.Window')
local Following = require('harness.ui.Following')
local sticky_bottom = require('harness.ui.sticky_bottom')

local eq = assert.are.same

describe('harness.ui.Following permutations:', function()
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

  local function bottom()
    return vim.fn.line('w$', win)
  end

  local function cursor()
    return vim.api.nvim_win_get_cursor(win)[1]
  end

  local function height()
    return vim.api.nvim_win_get_height(win)
  end

  local function top_text()
    return vim.api.nvim_buf_get_lines(bufnr, top() - 1, top(), false)[1]
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

  local function insert_at(row, count)
    local lines = {}

    for i = 1, count do
      lines[i] = 'child ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)
  end

  local function land()
    following:land(window(), function() end)
  end

  local function settle()
    if not following:resized(window()) then following:observe(window()) end
    following:sync(window())
  end

  local function redraw()
    following:sync(window())
  end

  local function hold_at(row)
    vim.api.nvim_win_set_cursor(win, { row, 0 })
    vim.cmd('normal! zt')
    settle()
  end

  local function assert_visible()
    local line = cursor()

    assert.is_true(line >= top() and line <= bottom(), 'cursor is in view')
    eq(-1, vim.fn.foldclosed(line), 'cursor is not inside a closed fold')
  end

  local function assert_follows(room)
    eq(true, following:follows(window()))
    eq(true, sticky_bottom.at_end(window()))

    if room ~= false then assert.is_true(sticky_bottom.room(window()) >= reserve, 'reserved rows are free') end

    assert_visible()
  end

  local function assert_holds()
    eq(true, following:holds(window()))
    assert_visible()
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

  local function scenario(name, intent, opts)
    it(name, function()
      if opts.setup then opts.setup() end

      if intent == 'follow' then
        land()
      else
        hold_at(opts.hold_at or 100)
      end

      local before = { top = top(), text = top_text(), cursor = cursor() }

      opts.action()

      if opts.sync == 'settle' then
        settle()
      else
        redraw()
      end

      if opts.check then opts.check(before, { top = top(), text = top_text(), cursor = cursor() }) end

      local expected = opts.expect or intent

      if expected == 'follow' then
        assert_follows(opts.room)
      else
        assert_holds()
      end
    end)
  end

  scenario('follow + append 1', 'follow', {
    action = function()
      append(1)
    end,
  })
  scenario('follow + append 20', 'follow', {
    action = function()
      append(20)
    end,
  })
  scenario('follow + append 100', 'follow', {
    action = function()
      append(100)
    end,
  })
  scenario('follow + rewrite grows', 'follow', {
    action = function()
      rewrite_tail(150, 80)
    end,
    room = false,
  })
  scenario('follow + rewrite shrinks', 'follow', {
    action = function()
      rewrite_tail(150, 10)
    end,
    room = false,
  })
  scenario('follow + insert above', 'follow', {
    action = function()
      insert_at(20, 15)
    end,
    room = false,
  })
  scenario('follow + insert below', 'follow', {
    action = function()
      insert_at(180, 5)
    end,
    room = false,
  })
  scenario('follow + height grows', 'follow', {
    sync = 'settle',
    action = function()
      vim.api.nvim_win_set_height(win, height() + 6)
    end,
  })
  scenario('follow + height shrinks', 'follow', {
    sync = 'settle',
    action = function()
      vim.api.nvim_win_set_height(win, height() - 6)
    end,
  })
  scenario('follow + width shrinks (wrap)', 'follow', {
    setup = function()
      vim.wo[win].wrap = true
    end,
    sync = 'settle',
    action = function()
      vim.api.nvim_win_set_width(win, vim.api.nvim_win_get_width(win) - 20)
    end,
  })
  scenario('follow + fold opens above', 'follow', {
    setup = function()
      vim.wo[win].foldmethod = 'manual'
      vim.wo[win].foldenable = true
      vim.cmd('10,20fold')
      vim.cmd('10foldopen')
    end,
    sync = 'settle',
    action = function()
      vim.cmd('10foldopen')
    end,
  })
  scenario('follow + fold closes above', 'follow', {
    setup = function()
      vim.wo[win].foldmethod = 'manual'
      vim.wo[win].foldenable = true
      vim.cmd('10,20fold')
    end,
    sync = 'settle',
    action = function()
      vim.cmd('10foldclose')
    end,
  })
  scenario('follow + reserve grows', 'follow', {
    sync = 'settle',
    action = function()
      reserve = 8
    end,
    check = function()
      assert.is_true(sticky_bottom.room(window()) >= 8)
    end,
  })
  scenario('follow + j at the tail', 'follow', {
    action = function()
      vim.cmd('normal! j')
    end,
    check = function(_, after)
      eq(vim.api.nvim_buf_line_count(bufnr), after.cursor)
    end,
  })
  scenario('follow + k scrolls up', 'follow', {
    sync = 'settle',
    action = function()
      for _ = 1, height() do
        vim.cmd('normal! k')
      end
    end,
    expect = 'hold',
  })

  scenario('hold + append 1', 'hold', {
    action = function()
      append(1)
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + append 20', 'hold', {
    action = function()
      append(20)
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + rewrite grows', 'hold', {
    action = function()
      rewrite_tail(150, 80)
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + rewrite shrinks past the anchor', 'hold', {
    action = function()
      rewrite_tail(20, 10)
    end,
    expect = 'follow',
    room = false,
  })
  scenario('hold + insert above keeps the row', 'hold', {
    action = function()
      insert_at(20, 15)
    end,
    check = function(before, after)
      eq(before.text, after.text)
    end,
  })
  scenario('hold + insert below keeps the top', 'hold', {
    action = function()
      insert_at(150, 5)
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + height shrinks', 'hold', {
    sync = 'settle',
    action = function()
      vim.api.nvim_win_set_height(win, height() - 6)
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + height grows', 'hold', {
    sync = 'settle',
    action = function()
      vim.api.nvim_win_set_height(win, height() + 6)
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + height shrinks with the cursor at the bottom', 'hold', {
    sync = 'settle',
    action = function()
      vim.api.nvim_win_set_cursor(win, { bottom(), 0 })
      vim.api.nvim_win_set_height(win, height() - 6)
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + fold opens above', 'hold', {
    setup = function()
      vim.wo[win].foldmethod = 'manual'
      vim.wo[win].foldenable = true
      vim.cmd('10,20fold')
    end,
    sync = 'settle',
    action = function()
      vim.cmd('10foldopen')
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + fold closes above', 'hold', {
    setup = function()
      vim.wo[win].foldmethod = 'manual'
      vim.wo[win].foldenable = true
      vim.cmd('10,20fold')
      vim.cmd('10foldopen')
    end,
    sync = 'settle',
    action = function()
      vim.cmd('10foldclose')
    end,
    check = function(before, after)
      eq(before.top, after.top)
    end,
  })
  scenario('hold + j moves down', 'hold', {
    sync = 'settle',
    action = function()
      vim.cmd('normal! j')
    end,
    check = function(before, after)
      eq(before.cursor + 1, after.cursor)
    end,
  })
  scenario('hold + k moves up', 'hold', {
    sync = 'settle',
    action = function()
      vim.cmd('normal! k')
    end,
    check = function(before, after)
      eq(before.cursor - 1, after.cursor)
    end,
  })
  scenario('hold + scroll to the end follows', 'hold', {
    sync = 'settle',
    action = function()
      vim.cmd('normal! G')
    end,
    expect = 'follow',
  })
end)

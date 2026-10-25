local Window = require('core.Window')
local Following = require('harness.ui.Following')
local sticky_bottom = require('harness.ui.sticky_bottom')

local eq = assert.are.same

describe('harness.ui.Following:', function()
  local win, bufnr, reserve, following

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

  it('remembers whether a window was last seen at the end, whichever way it was left', function()
    following:land(window(), function() end)
    eq(true, following:arrive(window()))
    assert.is_nil(following:arrive(window()))

    vim.cmd('normal! gg')
    following:track({ window() })
    eq(false, following:arrive(window()))
  end)

  it('forgets a closed window', function()
    following:land(window(), function() end)
    following:forget(win)
    assert.is_nil(following.windows[win])
  end)
end)

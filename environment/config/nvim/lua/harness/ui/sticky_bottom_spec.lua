local Window = require('core.Window')
local sticky_bottom = require('harness.ui.sticky_bottom')

local eq = assert.are.same

describe('harness.ui.sticky_bottom:', function()
  local win, bufnr

  local function fill(count)
    local lines = {}

    for i = 1, count do
      lines[i] = 'line ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  local function window()
    return Window(win)
  end

  local function room()
    local last = vim.api.nvim_buf_line_count(bufnr)

    return vim.fn.line('w0', win) + vim.api.nvim_win_get_height(win) - 1 - last
  end

  before_each(function()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    win = vim.api.nvim_get_current_win()
    bufnr = vim.api.nvim_get_current_buf()
    vim.wo[win].wrap = false
  end)

  it('keeps the offset within a third of the window', function()
    local height = vim.api.nvim_win_get_height(win)

    assert.is_true(sticky_bottom.margin(window()) <= math.floor(height / 3))
    assert.is_true(sticky_bottom.margin(window()) > 0)
  end)

  it('is at the end while the last line is in view, and not once scrolled away', function()
    fill(200)
    vim.cmd('normal! gg')
    eq(false, sticky_bottom.at_end(window()))
    vim.cmd('normal! G')
    eq(true, sticky_bottom.at_end(window()))
    vim.cmd('normal! gg')
    eq(false, sticky_bottom.at_end(window()))
  end)

  it('is at the end for a buffer that fits, and for a window that is gone', function()
    fill(3)
    eq(true, sticky_bottom.at_end(window()))
    eq(false, sticky_bottom.at_end(Window(-1)))
  end)

  it('pins the cursor to the last line with empty rows under it', function()
    fill(200)
    vim.cmd('normal! gg')
    sticky_bottom.pin(window())
    eq(200, vim.api.nvim_win_get_cursor(win)[1])
    eq(sticky_bottom.margin(window()), room())
  end)

  it('does not push a buffer that fits out of the window', function()
    fill(3)
    sticky_bottom.pin(window())
    eq(1, vim.fn.line('w0', win))
    eq(3, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it('keeps the newest line on the edge of the reserved rows as the stream grows', function()
    fill(200)
    sticky_bottom.pin(window())

    local margin = sticky_bottom.margin(window())

    eq(margin, room())

    for i = 1, margin + 3 do
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'more ' .. i })
      sticky_bottom.tail(window(), true)
      eq(margin, room())
    end
  end)

  it('uses the whole window when nothing is reserved', function()
    fill(200)
    sticky_bottom.pin(window(), 0)
    eq(0, room())
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'more' })
    sticky_bottom.tail(window(), true, 0)
    eq(0, room())
  end)

  it('scrolls by every row that grew past the bottom in one go', function()
    fill(200)
    sticky_bottom.pin(window())

    local extra = {}

    for i = 1, 40 do
      extra[i] = 'more ' .. i
    end

    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, extra)
    sticky_bottom.tail(window(), true)
    eq(240, vim.api.nvim_win_get_cursor(win)[1])
    eq(sticky_bottom.margin(window()), room())
  end)

  it('counts wrapped rows when it scrolls', function()
    vim.wo[win].wrap = true
    fill(200)
    sticky_bottom.pin(window())

    local wide = string.rep('word ', vim.api.nvim_win_get_width(win))

    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { wide, wide, wide })
    sticky_bottom.tail(window(), true)
    assert.is_true(vim.fn.line('w$', win) >= vim.api.nvim_buf_line_count(bufnr))
  end)

  it('moves the cursor only when asked to', function()
    fill(200)
    vim.cmd('normal! G')
    vim.api.nvim_win_set_cursor(win, { 150, 0 })
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'more' })
    sticky_bottom.tail(window(), false)
    assert.is_true(vim.api.nvim_win_get_cursor(win)[1] ~= 201)
    sticky_bottom.tail(window(), true)
    eq(201, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it('leaves a window scrolled away from the end where it is', function()
    fill(200)
    vim.cmd('normal! gg')
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'more' })

    local top = vim.fn.line('w0', win)

    if sticky_bottom.at_end(window()) then sticky_bottom.tail(window(), true) end
    eq(top, vim.fn.line('w0', win))
    eq(1, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it('scrolls just enough to free the rows asked for, and never back', function()
    fill(200)
    sticky_bottom.pin(window(), 0)

    local top = vim.fn.line('w0', win)

    sticky_bottom.hold(window(), 4)
    eq(4, room())
    eq(top + 4, vim.fn.line('w0', win))
    sticky_bottom.hold(window(), 1)
    eq(top + 4, vim.fn.line('w0', win))
  end)

  it('gives back only the spare rows when asked to release', function()
    fill(200)
    sticky_bottom.pin(window(), 6)
    sticky_bottom.release(window(), 4, 2)
    eq(2, room())
    sticky_bottom.release(window(), 4, 2)
    eq(2, room())
  end)

  it('re-reserves when the composer height setting changes, on the next text', function()
    local composer = require('harness.settings.composer')
    local saved = composer:get('height')

    composer:set('height', 1)
    fill(200)
    sticky_bottom.pin(window())

    local before = room()

    composer:set('height', 4)
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'more' })
    sticky_bottom.tail(window(), true)
    composer:set('height', saved)
    assert.is_true(room() > before)
  end)

  it('does nothing for a window that is gone', function()
    assert.has_no.errors(function()
      sticky_bottom.pin(Window(-1))
      sticky_bottom.tail(Window(-1), true)
    end)
  end)
end)

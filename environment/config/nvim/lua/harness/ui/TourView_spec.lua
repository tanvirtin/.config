local TourView = require('harness.ui.TourView')
local tour_type = require('harness.types.tour')

local eq = assert.are.same

local function real(path)
  return vim.uv.fs_realpath(path)
end

local function floats()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative ~= ''
  end, vim.api.nvim_tabpage_list_wins(0))
end

local function marks(buf, namespace)
  return vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
end

describe('harness.ui.TourView:', function()
  local dir, view, data

  before_each(function()
    vim.cmd('silent! only!')
    vim.cmd('enew!')
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')

    local lines = {}

    for i = 1, 40 do
      lines[i] = 'line ' .. i
    end

    vim.fn.writefile(lines, dir .. '/a.lua')
    vim.fn.writefile({ 'alpha', 'beta' }, dir .. '/b.lua')

    data = assert(tour_type.parse({
      title = 'Walk',
      summary = 'Two places.',
      steps = {
        { path = 'a.lua', line = 10, end_line = 12, title = 'First', note = 'The **first** place.' },
        { path = 'b.lua', line = 2, note = 'The second.' },
        { path = 'a.lua', line = 30, title = 'Back again' },
      },
    }, dir))
  end)

  after_each(function()
    if view then view:stop() end

    vim.cmd('silent! only!')
    vim.cmd('enew!')
    vim.fn.delete(dir, 'rf')
  end)

  local function note_text()
    local win = floats()[1]

    return win and table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
  end

  it('opens the first step\'s file at its lines, centres it and marks the range', function()
    view = TourView(data)

    assert.is_true(view:start())

    local buf = vim.api.nvim_get_current_buf()

    eq(real(dir .. '/a.lua'), real(vim.api.nvim_buf_get_name(buf)))
    eq(10, vim.api.nvim_win_get_cursor(0)[1])

    local shown = marks(buf, TourView.SHOW)

    eq({ 9, 12 }, { shown[1][2], shown[1][4].end_row })
    assert.truthy(shown[2][4].virt_text[1][1]:find('1/3 · First', 1, true))
  end)

  it('shows the note beside the code, with the summary on the first step only', function()
    view = TourView(data)
    view:start()

    eq(1, #floats())
    assert.truthy(note_text():find('Two places.', 1, true))
    assert.truthy(note_text():find('The **first** place.', 1, true))

    local config = vim.api.nvim_win_get_config(floats()[1])

    eq(false, config.focusable)
    assert.truthy(config.title[1][1]:find('1/3 · First', 1, true))

    view:next()

    eq(1, #floats())
    assert.is_nil(note_text():find('Two places.', 1, true))
    eq('The second.', note_text())
  end)

  it('goes to the next and previous step, across files, and clears the last range as it goes', function()
    view = TourView(data)
    view:start()

    local first = vim.api.nvim_get_current_buf()

    view:next()

    eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(0)))
    eq(2, vim.api.nvim_win_get_cursor(0)[1])
    eq({}, marks(first, TourView.SHOW))
    assert.is_true(#marks(0, TourView.SHOW) > 0)

    view:previous()

    eq(first, vim.api.nvim_get_current_buf())
    eq(10, vim.api.nvim_win_get_cursor(0)[1])
    eq(1, view.index)

    view:previous()
    eq(1, view.index)
  end)

  it('ends after the last step, taking the note, the marks and the keys with it', function()
    local stopped = 0

    view = TourView(data, {
      on_stop = function()
        stopped = stopped + 1
      end,
    })
    view:start()

    local buf = vim.api.nvim_get_current_buf()

    view:next()
    view:next()
    view:next()

    eq(0, view.index)
    eq(0, #floats())
    eq({}, marks(buf, TourView.SHOW))
    eq(1, stopped)
    eq(false, view:stop())
    eq(1, stopped)
  end)

  it('binds next, previous and stop on the code it shows, and unbinds them when it ends', function()
    view = TourView(data)
    view:start()

    local buf = vim.api.nvim_get_current_buf()

    local function mapped()
      return vim.tbl_map(function(map)
        return map.lhs
      end, vim.api.nvim_buf_get_keymap(buf, 'n'))
    end

    assert.is_true(vim.tbl_contains(mapped(), ']]'))
    assert.is_true(vim.tbl_contains(mapped(), '[['))

    vim.api.nvim_feedkeys(vim.keycode(']]'), 'x', false)
    eq(2, view.index)

    view:stop()

    assert.is_false(vim.tbl_contains(mapped(), ']]'))
  end)

  it('follows the code when lines are added above it, so coming back lands on the same place', function()
    view = TourView(data)
    view:start()

    local a = vim.api.nvim_get_current_buf()

    view:next()
    vim.api.nvim_buf_set_lines(a, 0, 0, false, { 'new 1', 'new 2', 'new 3' })
    view:previous()

    eq(13, vim.api.nvim_win_get_cursor(0)[1])
    eq('line 10', vim.api.nvim_buf_get_lines(a, 12, 13, false)[1])
  end)

  it('opens a split above for the code when every window is a harness one, leaving the transcript alone', function()
    local transcript = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_name(transcript, 'harness://t1 untitled')
    vim.api.nvim_win_set_buf(0, transcript)

    local harness_win = vim.api.nvim_get_current_win()

    view = TourView(data)

    assert.is_true(view:start())

    eq(transcript, vim.api.nvim_win_get_buf(harness_win))
    eq(2, #vim.api.nvim_tabpage_list_wins(0) - #floats())
    eq(real(dir .. '/a.lua'), real(vim.api.nvim_buf_get_name(0)))
    assert.is_not.equal(harness_win, vim.api.nvim_get_current_win())

    view:next()

    eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(0)))
    eq(2, #vim.api.nvim_tabpage_list_wins(0) - #floats())
  end)
end)

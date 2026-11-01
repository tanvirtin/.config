local TourView = require('harness.ui.TourView')
local tour = require('harness.ui.tour')
local tour_type = require('harness.types.tour')

local eq = assert.are.same

describe('harness.ui.tour:', function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'one', 'two', 'three' }, dir .. '/a.lua')
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  it('drafts a question that names the step, its code and its note, and ends where you type', function()
    local data = assert(tour_type.parse({
      title = 'Walk',
      steps = {
        { path = 'a.lua', line = 1 },
        { path = 'a.lua', line = 2, end_line = 3, title = 'Second', note = 'First line.\n\nSecond line.' },
      },
    }, dir))
    local view = TourView(data)

    view.index = 2

    local lines = vim.split(tour.step_draft(view), '\n', { plain = true })

    eq('[Tour "Walk", step 2/2: Second]', lines[1])
    eq(vim.fs.normalize(dir .. '/a.lua') .. ':2-3', lines[2])
    eq({ '> First line.', '> Second line.' }, { lines[3], lines[4] })
    assert.truthy(table.concat(lines, '\n'):find('tour_update', 1, true))
    eq('Question: ', lines[#lines])
  end)

  it('has nothing to ask about without a tour', function()
    eq({ false, 'no tour is running' }, { tour.ask_step() })
  end)

  it('says how to bring a stopped tour back', function()
    eq({ false, 'no tour is running; :HarnessTour resume brings back the last one' }, { tour.next('s1') })
  end)

  it('resumes the last tour at the step it stopped on', function()
    local data = assert(tour_type.parse({
      title = 'Walk',
      steps = {
        { path = 'a.lua', line = 1 },
        { path = 'a.lua', line = 2, title = 'Second' },
      },
    }, dir))

    assert.is_true(tour.start(data, { session = 's1' }))
    assert.is_true(tour.next('s1'))
    tour.stop('s1')

    assert.is_true(tour.resume('s1'))
    eq({ 2, 0 }, vim.api.nvim_win_get_cursor(0))

    tour.stop('s1')
    vim.cmd('silent! enew!')
  end)

  it('brings a stopped tour back on next', function()
    local data = assert(tour_type.parse({
      title = 'Walk',
      steps = {
        { path = 'a.lua', line = 1 },
        { path = 'a.lua', line = 2, title = 'Second' },
      },
    }, dir))

    assert.is_true(tour.start(data, { session = 's1' }))
    assert.is_true(tour.next('s1'))
    tour.stop('s1')

    assert.is_true(tour.next('s1'))
    eq({ 2, 0 }, vim.api.nvim_win_get_cursor(0))

    tour.stop('s1')
    vim.cmd('silent! enew!')
  end)

  it('will not start a tour that is not tied to a session', function()
    local data = assert(tour_type.parse({ title = 'Walk', steps = { { path = 'a.lua', line = 1 } } }, dir))

    eq({ false, 'a tour belongs to a session' }, { tour.start(data) })
  end)
end)

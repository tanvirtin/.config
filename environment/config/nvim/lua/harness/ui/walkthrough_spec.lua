local WalkthroughView = require('harness.ui.WalkthroughView')
local walkthrough = require('harness.ui.walkthrough')
local walkthrough_type = require('harness.types.walkthrough')
local walkthrough_store = require('harness.walkthrough_store')

local eq = assert.are.same

describe('harness.ui.walkthrough:', function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'one', 'two', 'three' }, dir .. '/a.lua')
    walkthrough.register_events()
  end)

  after_each(function()
    walkthrough_store.reset()
    vim.fn.delete(dir, 'rf')
  end)

  it('drafts a question that names the step, its code and its note, and ends where you type', function()
    local data = assert(walkthrough_type.parse({
      title = 'Walk',
      steps = {
        { path = 'a.lua', line = 1 },
        { path = 'a.lua', line = 2, end_line = 3, title = 'Second', note = 'First line.\n\nSecond line.' },
      },
    }, dir))
    local view = WalkthroughView(data)

    view.index = 2

    local lines = vim.split(walkthrough.step_draft(view), '\n', { plain = true })

    eq('[Walkthrough "Walk", step 2/2: Second]', lines[1])
    eq(vim.fs.normalize(dir .. '/a.lua') .. ':2-3', lines[2])
    eq({ '> First line.', '> Second line.' }, { lines[3], lines[4] })
    assert.truthy(table.concat(lines, '\n'):find('walkthrough_update', 1, true))
    eq('Question: ', lines[#lines])
  end)

  it('has nothing to ask about without a walkthrough', function()
    eq({ false, 'no walkthrough is running' }, { walkthrough.ask_step() })
  end)

  it('says how to bring a stopped walkthrough back', function()
    eq(
      { false, 'no walkthrough is running; :HarnessWalkthrough resume brings back the last one' },
      { walkthrough.next('s1') }
    )
  end)

  it('resumes the last walkthrough at the step it stopped on', function()
    local data = assert(walkthrough_type.parse({
      title = 'Walk',
      steps = {
        { path = 'a.lua', line = 1 },
        { path = 'a.lua', line = 2, title = 'Second' },
      },
    }, dir))

    assert.is_true(walkthrough.start(data, { session = 's1' }))
    assert.is_true(walkthrough.next('s1'))
    walkthrough.stop('s1')

    assert.is_true(walkthrough.resume('s1'))
    eq({ 2, 0 }, vim.api.nvim_win_get_cursor(0))

    walkthrough.stop('s1')
    vim.cmd('silent! enew!')
  end)

  it('keeps a resumed walkthrough running for the agent, so walkthrough_update still reaches it', function()
    local data = assert(walkthrough_type.parse({
      title = 'Walk',
      steps = {
        { path = 'a.lua', line = 1 },
        { path = 'a.lua', line = 2, note = 'Before.' },
      },
    }, dir))

    walkthrough_store.start('s1', data)
    walkthrough.stop('s1')

    assert.is_true(walkthrough.resume('s1'))
    eq(data, walkthrough_store.current('s1'))
    eq(true, (walkthrough_store.update('s1', { mode = 'note', note = 'After.' })))
    eq('After.', data.steps[1].note)

    walkthrough.stop('s1')
    vim.cmd('silent! enew!')
  end)

  it('brings a stopped walkthrough back on next', function()
    local data = assert(walkthrough_type.parse({
      title = 'Walk',
      steps = {
        { path = 'a.lua', line = 1 },
        { path = 'a.lua', line = 2, title = 'Second' },
      },
    }, dir))

    assert.is_true(walkthrough.start(data, { session = 's1' }))
    assert.is_true(walkthrough.next('s1'))
    walkthrough.stop('s1')

    assert.is_true(walkthrough.next('s1'))
    eq({ 2, 0 }, vim.api.nvim_win_get_cursor(0))

    walkthrough.stop('s1')
    vim.cmd('silent! enew!')
  end)

  it('will not start a walkthrough that is not tied to a session', function()
    local data = assert(walkthrough_type.parse({ title = 'Walk', steps = { { path = 'a.lua', line = 1 } } }, dir))

    eq({ false, 'a walkthrough belongs to a session' }, { walkthrough.start(data) })
  end)
end)

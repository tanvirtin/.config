local tour = require('harness.types.tour')

local eq = assert.are.same

describe('harness.types.tour:', function()
  local dir, file

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    file = dir .. '/a.lua'
    vim.fn.writefile({ 'one', 'two', 'three' }, file)
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  it('turns an agent\'s steps into a tour, resolving paths against the directory', function()
    local parsed = tour.parse({
      title = 'How it works',
      summary = 'A short walk.',
      steps = {
        { path = 'a.lua', line = 2, end_line = 3, title = 'The core', note = 'This is **it**.' },
        { path = file, line = 1 },
      },
    }, dir)

    eq('How it works', parsed.title)
    eq('A short walk.', parsed.summary)
    eq(2, #parsed.steps)
    eq({ vim.fs.normalize(file), 2, 3, 'The core', 'This is **it**.' }, {
      parsed.steps[1].path,
      parsed.steps[1].line,
      parsed.steps[1].end_line,
      parsed.steps[1].title,
      parsed.steps[1].note,
    })
    eq({ 1, 1, '' }, { parsed.steps[2].line, parsed.steps[2].end_line, parsed.steps[2].note })
  end)

  it('keeps a range from running backwards and a line from being zero', function()
    local parsed = tour.parse({ steps = { { path = 'a.lua', line = 0, end_line = -4 } } }, dir)

    eq({ 1, 1 }, { parsed.steps[1].line, parsed.steps[1].end_line })
    eq('Tour', parsed.title)
  end)

  it('says which step is wrong, so the agent can fix it', function()
    local parsed, err =
      tour.parse({ steps = { { path = 'a.lua', line = 1 }, { path = 'missing.lua', line = 1 } } }, dir)

    eq(nil, parsed)
    eq('step 2: no file missing.lua', err)
  end)

  it('refuses an empty tour and one too long to follow', function()
    eq('a tour needs at least one step', select(2, tour.parse({ steps = {} }, dir)))

    local steps = {}

    for i = 1, tour.MAX_STEPS + 1 do
      steps[i] = { path = 'a.lua', line = 1 }
    end

    assert.truthy(select(2, tour.parse({ steps = steps }, dir)):find('at most', 1, true))
  end)

  it('gathers several ranges under one step, the first naming where it starts', function()
    vim.fn.writefile({ 'x' }, dir .. '/b.lua')

    local parsed = tour.parse({
      steps = {
        { title = 'Section', ranges = { { path = 'a.lua', line = 2, end_line = 3 }, { path = 'b.lua', line = 1 } } },
      },
    }, dir)
    local step = parsed.steps[1]

    eq({ vim.fs.normalize(file), 2, 3 }, { step.path, step.line, step.end_line })
    eq(2, #step.ranges)
    eq(vim.fs.normalize(dir .. '/b.lua'), step.ranges[2].path)
  end)

  it('says which range of a step is wrong', function()
    local _, err =
      tour.parse({ steps = { { ranges = { { path = 'a.lua', line = 1 }, { path = 'nope.lua', line = 1 } } } } }, dir)

    eq('step 1: range 2: no file nope.lua', err)
  end)

  it('puts supporting steps after the core ones, keeping each group in order', function()
    local parsed = tour.parse({
      steps = {
        { path = 'a.lua', line = 1, title = 'test', supporting = true },
        { path = 'a.lua', line = 1, title = 'core one' },
        { path = 'a.lua', line = 1, title = 'docs', supporting = true },
        { path = 'a.lua', line = 1, title = 'core two' },
      },
    }, dir)

    eq(
      { 'core one', 'core two', 'test', 'docs' },
      vim.tbl_map(function(step)
        return step.title
      end, parsed.steps)
    )
    eq({ false, true }, { parsed.steps[1].supporting, parsed.steps[3].supporting })
  end)
end)

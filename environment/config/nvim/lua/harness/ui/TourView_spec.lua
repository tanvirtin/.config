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

  it('starts at a given step, so a stopped tour can come back where it was', function()
    view = TourView(data)

    assert.is_true(view:start(2))
    eq(2, view.index)
    eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())))
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

  it('ends itself, note and all, when the code buffer is closed under it', function()
    view = TourView(data)
    view:start()

    vim.cmd('bwipeout! ' .. vim.api.nvim_get_current_buf())

    vim.wait(200, function()
      return not view:is_open()
    end)

    eq(false, view:is_open())
    eq(0, #floats())
  end)

  it('ends itself, note and all, when its code window is closed', function()
    vim.cmd('split')

    view = TourView(data)
    view:start()

    eq(1, #floats())

    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)

    vim.wait(200, function()
      return not view:is_open()
    end)

    eq(false, view:is_open())
    eq(0, #floats())
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

  it('moves its current step to a selection attached to the composer', function()
    view = TourView(data)

    view:start()

    eq(true, view:select(dir .. '/a.lua', 14, 16))
    eq({ 14, 16 }, { view.tour.steps[1].line, view.tour.steps[1].end_line })

    local shown = marks(vim.api.nvim_get_current_buf(), TourView.SHOW)

    eq({ 13, 16 }, { shown[1][2], shown[1][4].end_row })
    eq(false, view:select(dir .. '/elsewhere.lua', 1, 1))
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

  it('tiles the transcript to the right and opens the code beside it when every window is a harness one', function()
    local transcript = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_name(transcript, 'harness://t1 untitled')
    vim.api.nvim_win_set_buf(0, transcript)

    local harness_win = vim.api.nvim_get_current_win()

    view = TourView(data)

    assert.is_true(view:start())

    eq(transcript, vim.api.nvim_win_get_buf(harness_win))
    eq(2, #vim.api.nvim_tabpage_list_wins(0) - #floats())
    eq(real(dir .. '/a.lua'), real(vim.api.nvim_buf_get_name(0)))

    local code = vim.api.nvim_get_current_win()
    local spec = require('harness.settings').transcript
    local total = vim.api.nvim_win_get_width(code) + vim.api.nvim_win_get_width(harness_win)

    eq(0, vim.api.nvim_win_get_position(code)[2])
    assert.is_true(vim.api.nvim_win_get_position(harness_win)[2] > 0)
    eq(
      math.max(spec:get('tile_min_width'), math.floor(total * spec:get('tile_width'))),
      vim.api.nvim_win_get_width(harness_win)
    )

    view:next()

    eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(0)))
    eq(2, #vim.api.nvim_tabpage_list_wins(0) - #floats())
  end)

  describe('when the agent changes the tour', function()
    local function step(fields)
      return assert(tour_type.step(vim.tbl_extend('force', { path = dir .. '/b.lua', line = 1 }, fields), dir))
    end

    it('inserts steps after the current one and moves to the first of them', function()
      view = TourView(data)
      view:start()

      assert.is_true(view:insert({ step({ title = 'Aside', note = 'extra' }), step({ line = 2, title = 'Aside 2' }) }))

      eq(2, view.index)
      eq({ 'First', 'Aside', 'Aside 2', nil, 'Back again' }, {
        view.tour.steps[1].title,
        view.tour.steps[2].title,
        view.tour.steps[3].title,
        nil,
        view.tour.steps[5].title,
      })
      eq(5, #view.tour.steps)
      eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(0)))
      assert.truthy(note_text():find('extra', 1, true))
    end)

    it('keeps the later steps tracking their code after an insert shifts them', function()
      view = TourView(data)
      view:start()
      view:next()
      view:next()

      local a = vim.fn.bufnr(dir .. '/a.lua')

      view:previous()
      view:previous()
      view:insert({ step({}) })
      vim.api.nvim_buf_set_lines(a, 0, 0, false, { 'x', 'y' })
      view:show(#view.tour.steps)

      eq(32, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('replaces everything after the current step', function()
      view = TourView(data)
      view:start()

      assert.is_true(view:replace_rest({ step({ title = 'New path' }) }))

      eq(2, #view.tour.steps)
      eq({ 2, 'New path' }, { view.index, view.tour.steps[2].title })
    end)

    it('rewrites the current step\'s note and stays on it', function()
      view = TourView(data)
      view:start()
      view:next()

      assert.is_true(view:annotate('A clearer note.'))

      eq(2, view.index)
      eq('A clearer note.', note_text())
    end)

    it('applies an update by its mode, and refuses one when the tour is not showing', function()
      view = TourView(data)

      eq({ false, 'the tour is not showing' }, { view:apply({ mode = 'note', note = 'x' }) })

      view:start()
      view:apply({ mode = 'note', note = 'via apply' })

      assert.truthy(note_text():find('via apply', 1, true))
    end)

    it('asks about the step on its key, through the callback it was given', function()
      local asked

      view = TourView(data, {
        on_ask = function(shown)
          asked = shown.index
        end,
      })
      view:start()
      view:next()
      vim.api.nvim_feedkeys('ga', 'x', false)

      eq(2, asked)
    end)
  end)

  describe('a tour of a commit that is not checked out', function()
    local repo, old

    local function sh(...)
      local result = vim.system({ 'git', '-C', repo, ... }, { text = true }):wait()

      assert(result.code == 0, result.stderr)

      return vim.trim(result.stdout)
    end

    before_each(function()
      repo = vim.fn.tempname()
      vim.fn.mkdir(repo, 'p')
      repo = vim.uv.fs_realpath(repo)
      sh('init', '-q', '-b', 'main')
      sh('config', 'user.email', 't@example.com')
      sh('config', 'user.name', 'T')
      sh('config', 'commit.gpgsign', 'false')
      vim.fn.writefile({ 'old 1', 'old 2', 'old 3' }, repo .. '/a.lua')
      sh('add', '.')
      sh('commit', '-q', '-m', 'old')
      old = sh('rev-parse', 'HEAD')
      vim.fn.writefile({ 'new 1', 'new 2', 'new 3', 'new 4' }, repo .. '/a.lua')
      sh('commit', '-q', '-am', 'new')
    end)

    after_each(function()
      vim.fn.delete(repo, 'rf')
    end)

    it('shows the file as it was at that commit, read-only, and says which commit', function()
      local parsed = assert(tour_type.parse({ steps = { { path = 'a.lua', line = 2, title = 'Then' } } }, repo, {
        rev = old,
        root = repo,
        check = function()
          return true
        end,
      }))

      view = TourView(parsed)
      assert.is_true(view:start())

      local buf = vim.api.nvim_get_current_buf()

      eq('rev://' .. old:sub(1, 7) .. '/a.lua', vim.api.nvim_buf_get_name(buf):match('rev://.*$'))
      eq({ 'old 1', 'old 2', 'old 3' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      eq(false, vim.bo[buf].modifiable)
      eq('lua', vim.bo[buf].filetype)
      eq(2, vim.api.nvim_win_get_cursor(0)[1])
      assert.truthy(marks(buf, TourView.SHOW)[2][4].virt_text[1][1]:find('@' .. old:sub(1, 7), 1, true))

      view:stop()

      eq(false, vim.api.nvim_buf_is_valid(buf))
    end)
  end)
end)

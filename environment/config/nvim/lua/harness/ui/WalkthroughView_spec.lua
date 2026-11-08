local WalkthroughView = require('harness.ui.WalkthroughView')
local walkthrough_type = require('harness.types.walkthrough')

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

describe('harness.ui.WalkthroughView:', function()
  local dir, view, data

  local note_mode

  before_each(function()
    note_mode = require('harness.settings').walkthrough:get('note')
    require('harness.settings').walkthrough:assign({ note = 'float' })
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

    data = assert(walkthrough_type.parse({
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

    require('harness.settings').walkthrough:assign({ note = note_mode })

    vim.cmd('silent! only!')
    vim.cmd('enew!')
    vim.fn.delete(dir, 'rf')
  end)

  local function note_text()
    local win = floats()[1]

    return win and table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
  end

  describe('with the note inline', function()
    before_each(function()
      require('harness.settings').walkthrough:assign({ note = 'inline' })
    end)

    local function note_rows(buf)
      local rows = {}

      for _, mark in ipairs(marks(buf, WalkthroughView.NOTE)) do
        for _, line in ipairs(mark[4].virt_lines or {}) do
          rows[#rows + 1] = table.concat(vim.tbl_map(function(chunk)
            return chunk[1]
          end, line))
        end
      end

      return rows
    end

    it('draws the note above the step\'s lines, with no float, and puts both at the top of the window', function()
      view = WalkthroughView(data)
      view:start()

      local buf = vim.api.nvim_get_current_buf()
      local rows = note_rows(buf)
      local shown = marks(buf, WalkthroughView.NOTE)[1]

      eq(0, #floats())
      eq(9, shown[2])
      assert.truthy(rows[1]:find('1/3 · First', 1, true))
      assert.truthy(table.concat(rows, '\n'):find('The first place.', 1, true))
      eq(10, vim.fn.line('w0'))
      eq(#rows, vim.fn.winsaveview().topfill)
    end)

    it('moves the note with the step and takes it away when the walkthrough ends', function()
      view = WalkthroughView(data)
      view:start()

      local first = vim.api.nvim_get_current_buf()

      view:next()

      eq(0, #marks(first, WalkthroughView.NOTE))
      assert.truthy(table.concat(note_rows(vim.api.nvim_get_current_buf()), '\n'):find('The second.', 1, true))

      view:stop()
      view = nil

      eq(0, #marks(vim.api.nvim_get_current_buf(), WalkthroughView.NOTE))
    end)
  end)

  it('opens the first step\'s file at its lines, centres it and marks the range', function()
    view = WalkthroughView(data)

    assert.is_true(view:start())

    local buf = vim.api.nvim_get_current_buf()

    eq(real(dir .. '/a.lua'), real(vim.api.nvim_buf_get_name(buf)))
    eq(10, vim.api.nvim_win_get_cursor(0)[1])

    local shown = marks(buf, WalkthroughView.SHOW)

    eq({ 9, 12 }, { shown[1][2], shown[1][4].end_row })
    assert.truthy(shown[2][4].virt_text[1][1]:find('1/3 · First', 1, true))
  end)

  it('starts at a given step, so a stopped walkthrough can come back where it was', function()
    view = WalkthroughView(data)

    assert.is_true(view:start(2))
    eq(2, view.index)
    eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())))
  end)

  it('shows the note beside the code, with the summary on the first step only', function()
    view = WalkthroughView(data)
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

  it('shows that a note is being written for a step without one, fills it in, and fetches the next ahead', function()
    local asked, pending = {}, {}

    view = WalkthroughView(data, {
      write_note = function(index, done)
        asked[#asked + 1] = { index, done ~= nil }
        if done then pending[index] = done end
      end,
    })
    view:start(3)

    assert.truthy(note_text():find(WalkthroughView.WRITING, 1, true))
    eq({ { 3, true } }, asked)

    data.steps[3].note = 'Written.'
    pending[3]('Written.')

    eq('Written.', note_text())
  end)

  it('says why a note could not be written, and asks for the next step\'s note ahead of time', function()
    local asked = {}

    data.steps[2].note = ''
    view = WalkthroughView(data, {
      write_note = function(index, done)
        asked[#asked + 1] = index
        if done then done(nil, 'the reader did not start') end
      end,
    })
    view:start(2)

    eq({ 2, 3 }, asked)
    assert.truthy(note_text():find('Could not write a note: the reader did not start', 1, true))
  end)

  it('marks a step understood and back, in its title and the overview', function()
    view = WalkthroughView(data)
    view:start()

    assert.is_true(view:toggle_understood())
    eq(true, data.steps[1].understood)
    assert.truthy(vim.api.nvim_win_get_config(floats()[1]).title[1][1]:find('✓ understood', 1, true))
    assert.truthy(vim.api.nvim_win_get_config(floats()[1]).footer[1][1]:find('g. not yet', 1, true))

    view:overview()

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    eq('1 of 3 understood', lines[2])
    assert.truthy(lines[vim.fn.match(lines, 'First') + 1]:find('| ✓ |', 1, true))
    eq(false, view:toggle_understood())

    view:next()
    view:previous()
    view:toggle_understood()
    eq(false, data.steps[1].understood)
  end)

  it('draws the step\'s function with what calls it and what it calls, and opens one from the diagram', function()
    vim.fn.writefile({
      'local M = {}',
      '',
      'function M.refresh()',
      '  return M.expiry()',
      'end',
      '',
      'function M.expiry()',
      '  return 1',
      'end',
      '',
      'function M.login()',
      '  return M.refresh()',
      'end',
    }, dir .. '/m.lua')

    view = WalkthroughView(assert(walkthrough_type.parse({
      title = 'Calls',
      steps = { { path = 'm.lua', line = 4, title = 'Refresh', note = 'Refreshes.' } },
    }, dir)))
    view:start()

    assert.is_true(view:diagram())

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local drawn = table.concat(lines, '\n')

    assert.truthy(drawn:find('│ M.refresh │', 1, true))
    assert.truthy(drawn:find('M.login', 1, true))
    assert.truthy(drawn:find('└─▶ M.expiry', 1, true))
    eq('M.login  m.lua:12 ─┐', lines[1])
    eq(1, vim.api.nvim_win_get_cursor(0)[1])

    vim.api.nvim_win_set_cursor(0, { vim.fn.match(lines, 'M.expiry') + 1, 0 })
    vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

    eq(7, vim.api.nvim_win_get_cursor(0)[1])
    assert.truthy(note_text():find('From the diagram of `M.refresh`', 1, true))

    view:next()
    eq(4, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it('goes to the next and previous step, across files, and clears the last range as it goes', function()
    view = WalkthroughView(data)
    view:start()

    local first = vim.api.nvim_get_current_buf()

    view:next()

    eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(0)))
    eq(2, vim.api.nvim_win_get_cursor(0)[1])
    eq({}, marks(first, WalkthroughView.SHOW))
    assert.is_true(#marks(0, WalkthroughView.SHOW) > 0)

    view:previous()

    eq(first, vim.api.nvim_get_current_buf())
    eq(10, vim.api.nvim_win_get_cursor(0)[1])
    eq(1, view.index)

    view:previous()
    eq(1, view.index)
  end)

  it('skips steps by a count, stopping at the ends without ending the walkthrough', function()
    view = WalkthroughView(data)
    view:start()

    view:next(99)
    eq(#data.steps, view.index)
    assert.is_true(view:is_open())

    view:previous(99)
    eq(1, view.index)
  end)

  it('offers back only after the first step, and finish on the last', function()
    view = WalkthroughView(data)
    view:start()

    local keys = require('harness.settings').keymaps:get('walkthrough')

    assert.is_nil(view:_footer(1):find(keys.previous .. ' back', 1, true))
    assert.is_truthy(view:_footer(2):find(keys.previous .. ' back', 1, true))
    assert.is_truthy(view:_footer(#data.steps):find(keys.next .. ' finish', 1, true))
  end)

  it('ends after the last step, taking the note, the marks and the keys with it', function()
    local stopped = 0

    view = WalkthroughView(data, {
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
    eq({}, marks(buf, WalkthroughView.SHOW))
    eq(1, stopped)
    eq(false, view:stop())
    eq(1, stopped)
  end)

  it('ends itself, note and all, when the code buffer is closed under it', function()
    view = WalkthroughView(data)
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

    view = WalkthroughView(data)
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
    view = WalkthroughView(data)
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
    view = WalkthroughView(data)

    view:start()

    eq(true, view:select(dir .. '/a.lua', 14, 16))
    eq({ 14, 16 }, { view.walkthrough.steps[1].line, view.walkthrough.steps[1].end_line })

    local shown = marks(vim.api.nvim_get_current_buf(), WalkthroughView.SHOW)

    eq({ 13, 16 }, { shown[1][2], shown[1][4].end_row })
    eq(false, view:select(dir .. '/elsewhere.lua', 1, 1))
  end)

  it('follows the code when lines are added above it, so coming back lands on the same place', function()
    view = WalkthroughView(data)
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

    view = WalkthroughView(data)

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

  describe('when the agent changes the walkthrough', function()
    local function step(fields)
      return assert(walkthrough_type.step(vim.tbl_extend('force', { path = dir .. '/b.lua', line = 1 }, fields), dir))
    end

    it('inserts steps after the current one and moves to the first of them', function()
      view = WalkthroughView(data)
      view:start()

      assert.is_true(view:insert({ step({ title = 'Aside', note = 'extra' }), step({ line = 2, title = 'Aside 2' }) }))

      eq(2, view.index)
      eq({ 'First', 'Aside', 'Aside 2', nil, 'Back again' }, {
        view.walkthrough.steps[1].title,
        view.walkthrough.steps[2].title,
        view.walkthrough.steps[3].title,
        nil,
        view.walkthrough.steps[5].title,
      })
      eq(5, #view.walkthrough.steps)
      eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(0)))
      assert.truthy(note_text():find('extra', 1, true))
    end)

    it('keeps the later steps tracking their code after an insert shifts them', function()
      view = WalkthroughView(data)
      view:start()
      view:next()
      view:next()

      local a = vim.fn.bufnr(dir .. '/a.lua')

      view:previous()
      view:previous()
      view:insert({ step({}) })
      vim.api.nvim_buf_set_lines(a, 0, 0, false, { 'x', 'y' })
      view:show(#view.walkthrough.steps)

      eq(32, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('replaces everything after the current step', function()
      view = WalkthroughView(data)
      view:start()

      assert.is_true(view:replace_rest({ step({ title = 'New path' }) }))

      eq(2, #view.walkthrough.steps)
      eq({ 2, 'New path' }, { view.index, view.walkthrough.steps[2].title })
    end)

    it('rewrites the current step\'s note and stays on it', function()
      view = WalkthroughView(data)
      view:start()
      view:next()

      assert.is_true(view:annotate('A clearer note.'))

      eq(2, view.index)
      eq('A clearer note.', note_text())
    end)

    it('applies an update by its mode, and refuses one when the walkthrough is not showing', function()
      view = WalkthroughView(data)

      eq({ false, 'the walkthrough is not showing' }, { view:apply({ mode = 'note', note = 'x' }) })

      view:start()
      view:apply({ mode = 'note', note = 'via apply' })

      assert.truthy(note_text():find('via apply', 1, true))
    end)

    it('asks about the step on its key, through the callback it was given', function()
      local asked

      view = WalkthroughView(data, {
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

  describe('a walkthrough of a commit that is not checked out', function()
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
      local parsed = assert(walkthrough_type.parse({ steps = { { path = 'a.lua', line = 2, title = 'Then' } } }, repo, {
        rev = old,
        root = repo,
        check = function()
          return true
        end,
      }))

      view = WalkthroughView(parsed)
      assert.is_true(view:start())

      local buf = vim.api.nvim_get_current_buf()

      eq('rev://' .. old:sub(1, 7) .. '/a.lua', vim.api.nvim_buf_get_name(buf):match('rev://.*$'))
      eq({ 'old 1', 'old 2', 'old 3' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      eq(false, vim.bo[buf].modifiable)
      eq('lua', vim.bo[buf].filetype)
      eq(2, vim.api.nvim_win_get_cursor(0)[1])
      assert.truthy(marks(buf, WalkthroughView.SHOW)[2][4].virt_text[1][1]:find('@' .. old:sub(1, 7), 1, true))

      view:stop()

      eq(false, vim.api.nvim_buf_is_valid(buf))
    end)

    local function review()
      return assert(
        walkthrough_type.parse({ steps = { { path = 'a.lua', line = 1, end_line = 4, title = 'All of it' } } }, repo, {
          base = old,
          root = repo,
        })
      )
    end

    it('shows a file the range adds as all added lines, instead of failing to read its base', function()
      vim.fn.writefile({ 'new 1', 'new 2' }, repo .. '/n.lua')
      sh('add', '.')
      sh('commit', '-q', '-m', 'add n')

      local scope = assert(require('harness.walkthrough_scope').compute(repo, old, 'HEAD'))
      local data = assert(walkthrough_type.parse({ steps = { { path = 'n.lua', line = 1, end_line = 2 } } }, repo, {
        base = old,
        root = repo,
        scope = scope,
      }))

      view = WalkthroughView(data)
      assert.is_true(view:start())

      local added = 0

      for _, mark in ipairs(marks(vim.api.nvim_get_current_buf(), WalkthroughView.SHOW)) do
        if mark[4].line_hl_group then added = added + 1 end
      end

      eq(2, added)
      eq(1, #floats())
    end)

    it('shows a step of a review as a diff against the base, in the code itself', function()
      view = WalkthroughView(review())
      assert.is_true(view:start())

      local buf = vim.api.nvim_get_current_buf()
      local added, removed = 0, {}

      for _, mark in ipairs(marks(buf, WalkthroughView.SHOW)) do
        if mark[4].line_hl_group then added = added + 1 end

        for _, line in ipairs(mark[4].virt_lines or {}) do
          removed[#removed + 1] = vim.trim(line[1][1])
        end
      end

      eq({ 'new 1', 'new 2', 'new 3', 'new 4' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      eq(4, added)
      eq({ 'old 1', 'old 2', 'old 3' }, removed)
      eq(true, vim.bo[buf].modifiable)
    end)

    it('lays the base beside the code in diff mode when split fits, and takes it away at the end', function()
      local spec = require('harness.settings').walkthrough
      local saved = { spec:get('diff_layout'), spec:get('split_min_width') }

      spec:assign({ diff_layout = 'split', split_min_width = 0 })

      view = WalkthroughView(review())
      assert.is_true(view:start())

      local code = vim.api.nvim_get_current_win()
      local wins = vim.tbl_filter(function(win)
        return vim.api.nvim_win_get_config(win).relative == ''
      end, vim.api.nvim_tabpage_list_wins(0))

      eq(2, #wins)
      eq(true, vim.wo[code].diff)

      local other = wins[1] == code and wins[2] or wins[1]

      eq({ 'old 1', 'old 2', 'old 3' }, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(other), 0, -1, false))

      view:stop()
      view = nil
      spec:assign({ diff_layout = saved[1], split_min_width = saved[2] })

      eq(false, vim.api.nvim_win_is_valid(other))
      eq(false, vim.wo[code].diff)
    end)
  end)

  describe('a step over several ranges', function()
    before_each(function()
      data = assert(walkthrough_type.parse({
        title = 'Sections',
        steps = {
          {
            title = 'Core',
            ranges = { { path = 'a.lua', line = 5 }, { path = 'b.lua', line = 1 } },
          },
          { path = 'a.lua', line = 20, title = 'Tests', supporting = true },
          { path = 'a.lua', line = 30, title = 'More' },
        },
      }, dir))
    end)

    it('walks each range, then into the next step, and back again', function()
      view = WalkthroughView(data)
      view:start()

      eq('Core', data.steps[1].title)
      eq('More', data.steps[2].title)
      eq('Tests', data.steps[3].title)

      view:next_range()
      eq({ 1, 2 }, { view.index, view.part })
      eq(real(dir .. '/b.lua'), real(vim.api.nvim_buf_get_name(0)))
      assert.truthy(vim.api.nvim_win_get_config(floats()[1]).title[1][1]:find('Core · 2/2', 1, true))

      view:next_range()
      eq({ 2, 1 }, { view.index, view.part })

      view:previous_range()
      eq({ 1, 2 }, { view.index, view.part })

      view:next()
      eq({ 2, 1 }, { view.index, view.part })
    end)

    it('marks the steps seen in the overview, and opens a hunk no step covers from it', function()
      data.uncovered = { { id = 'h9', path = 'a.lua', absolute = dir .. '/a.lua', first = 38, last = 39 } }
      view = WalkthroughView(data)
      view:start()
      view:next()

      assert.is_true(view:overview())

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local function line(pattern)
        return lines[vim.fn.match(lines, pattern) + 1]
      end

      assert.truthy(line('Core'):find('| · |', 1, true))
      assert.truthy(line('More'):find('▸', 1, true))
      assert.truthy(line('Tests'):find('supporting', 1, true))
      eq('- ○ a.lua · 1 hunk · h9', line('h9'))

      vim.api.nvim_win_set_cursor(0, { vim.fn.match(lines, 'h9') + 1, 0 })
      assert.is_true(view:open_row())
      eq(38, vim.api.nvim_win_get_cursor(0)[1])
      assert.truthy(note_text():find('No step covers', 1, true))
      eq(2, view.index)

      view:next()
      eq(2, view.index)
      eq(30, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('steps through the hunks no step covers with ]c and [c, saying which one of how many', function()
      data.uncovered = {
        { id = 'h8', path = 'a.lua', absolute = dir .. '/a.lua', first = 34, last = 34 },
        { id = 'h9', path = 'a.lua', absolute = dir .. '/a.lua', first = 38, last = 39 },
      }
      view = WalkthroughView(data)
      view:start()

      assert.is_true(view:visit(data.uncovered[1]))
      assert.truthy(note_text():find('1 of 2 not covered', 1, true))

      view:next_range()
      eq(38, vim.api.nvim_win_get_cursor(0)[1])
      assert.truthy(note_text():find('2 of 2 not covered', 1, true))

      view:next_range()
      eq(38, vim.api.nvim_win_get_cursor(0)[1])

      view:previous_range()
      eq(34, vim.api.nvim_win_get_cursor(0)[1])

      view:next()
      eq(1, view.index)
    end)
  end)
end)

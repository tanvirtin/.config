local tools = require('nvim_mcp.tools')
local tour_store = require('harness.tour_store')
local tour_tools = require('harness.tour_tools')

local eq = assert.are.same

describe('harness.tour_tools:', function()
  before_each(function()
    tour_store.reset()
    tour_tools.register()
  end)

  after_each(function()
    tour_store.reset()
    tools.unregister('tour')
  end)

  it('registers a tour_start tool the agent can read about', function()
    local definition = vim.tbl_filter(function(entry)
      return entry.name == 'tour_start'
    end, tools.definitions())[1]

    assert.truthy(definition)
    assert.truthy(definition.summary:find('Walk the user through', 1, true))
  end)

  it('hands a valid tour to the store and says how many steps it holds', function()
    local seen

    tour_store.on(function(kind, tour)
      seen = { kind, tour.title, #tour.steps }
    end)

    local result = tools.run('tour_start', {
      title = 'Config',
      steps = { { path = 'init.lua', line = 1, note = 'Start here.' } },
    })

    eq({ 'start', 'Config', 1 }, seen)
    eq({ title = 'Config', steps = 1 }, result)
  end)

  it('tells the agent which step has a path that does not exist', function()
    local ok, err = pcall(tools.run, 'tour_start', {
      title = 'Bad',
      steps = { { path = 'init.lua', line = 1 }, { path = 'no/such/file.lua', line = 3 } },
    })

    eq(false, ok)
    assert.truthy(tostring(err):find('step 2: no file no/such/file.lua', 1, true))
    eq(nil, tour_store.current())
  end)

  describe('tour_update', function()
    local function start()
      tour_store.start({ title = 'Config', steps = { { title = 'one' } } })
    end

    it('passes parsed steps to whoever follows the tour', function()
      local seen

      start()
      tour_store.on(function(kind, _, update)
        if kind == 'update' then seen = update end
      end)

      local result = tools.run('tour_update', {
        mode = 'insert',
        steps = { { path = 'init.lua', line = 2, note = 'More.' } },
      })

      eq('insert', seen.mode)
      eq(1, #seen.steps)
      eq(2, seen.steps[1].line)
      eq({ title = 'Config', steps = 1 }, result)
    end)

    it('rewrites a note without needing steps', function()
      local seen

      start()
      tour_store.on(function(kind, _, update)
        if kind == 'update' then seen = update end
      end)
      tools.run('tour_update', { mode = 'note', note = 'Clearer.' })

      eq({ 'note', 'Clearer.' }, { seen.mode, seen.note })
    end)

    it('says what is missing, and that there is no tour to change', function()
      local function message(args)
        return tostring(select(2, pcall(tools.run, 'tour_update', args)))
      end

      assert.truthy(message({ mode = 'note', note = 'x' }):find('no tour is running', 1, true))

      start()

      assert.truthy(message({ mode = 'insert' }):find('needs steps', 1, true))
      assert.truthy(message({ mode = 'note' }):find('needs a note', 1, true))
      assert.truthy(
        message({ mode = 'insert', steps = { { path = 'nope.lua', line = 1 } } }):find('step 1: no file', 1, true)
      )
    end)
  end)

  describe('reviewing a range of commits', function()
    local repo, base, middle, saved

    local function sh(...)
      local result = vim.system({ 'git', '-C', repo, ... }, { text = true }):wait()

      assert(result.code == 0, result.stderr)

      return vim.trim(result.stdout)
    end

    before_each(function()
      saved = vim.fn.getcwd()
      repo = vim.fn.tempname()
      vim.fn.mkdir(repo, 'p')
      repo = vim.uv.fs_realpath(repo)
      sh('init', '-q', '-b', 'main')
      sh('config', 'user.email', 't@example.com')
      sh('config', 'user.name', 'T')
      sh('config', 'commit.gpgsign', 'false')
      vim.fn.writefile({ 'a1', 'a2', 'a3', 'a4', 'a5', 'a6' }, repo .. '/a.lua')
      sh('add', '.')
      sh('commit', '-q', '-m', 'start')
      base = sh('rev-parse', 'HEAD')
      sh('checkout', '-q', '-b', 'feature')
      vim.fn.writefile({ 'a1', 'A2', 'a3', 'a4', 'a5', 'A6' }, repo .. '/a.lua')
      vim.fn.writefile({ 'b1', 'b2' }, repo .. '/b.lua')
      sh('add', '.')
      sh('commit', '-q', '-m', 'change a, add b')
      middle = sh('rev-parse', 'HEAD')
      vim.fn.writefile({ 'a1', 'A2', 'a3', 'a4', 'a5', 'A6', 'a7' }, repo .. '/a.lua')
      sh('add', '.')
      sh('commit', '-q', '-m', 'extend a')
      vim.cmd('cd ' .. vim.fn.fnameescape(repo))
    end)

    after_each(function()
      vim.cmd('cd ' .. vim.fn.fnameescape(saved))
      vim.fn.delete(repo, 'rf')
    end)

    it('works the range out from git and hands back the rev to tour', function()
      local scope = tools.run('tour_scope', { base = base, head = middle })

      eq({ base:sub(1, 7), middle:sub(1, 7), middle, false }, { scope.base, scope.head, scope.rev, scope.checked_out })
      eq(
        { 'a.lua', 'b.lua' },
        vim.tbl_map(function(file)
          return file.path
        end, scope.files)
      )
      eq(1, scope.commit_count)
      assert.truthy(scope.next:find('tour_start', 1, true))
    end)

    it('names a commit that is not here, instead of reviewing nothing', function()
      local ok, err = pcall(tools.run, 'tour_scope', { base = 'nope1234', head = middle })

      eq(false, ok)
      assert.truthy(tostring(err):find('no commit "nope1234"', 1, true))
    end)

    it('tours a commit that is not checked out from git, and says what the steps leave out', function()
      tools.run('tour_scope', { base = base, head = middle })

      local reply = tools.run('tour_start', {
        title = 'Review',
        rev = middle,
        steps = { { path = 'a.lua', line = 2, note = 'a2 changed.' } },
      })
      local tour = tour_store.current()

      eq(middle, tour.rev)
      eq(vim.fs.normalize(repo), tour.root)
      eq(2, reply.uncovered_count)
      eq({ 'a.lua', 6, 6 }, { reply.uncovered[1].path, reply.uncovered[1].first, reply.uncovered[1].last })
      assert.truthy(reply.note:find('tour_update', 1, true))
    end)

    it('says it is complete once every hunk has a step, and checks added steps against the commit', function()
      tools.run('tour_scope', { base = base, head = middle })
      tools.run('tour_start', { title = 'Review', rev = middle, steps = { { path = 'a.lua', line = 2 } } })
      tour_store.on(function(kind, tour, update)
        if kind == 'update' then vim.list_extend(tour.steps, update.steps) end
      end)

      local reply = tools.run('tour_update', {
        mode = 'insert',
        steps = { { path = 'a.lua', line = 6 }, { path = 'b.lua', line = 1, end_line = 2 } },
      })

      eq(3, reply.steps)
      eq(nil, reply.uncovered)
      assert.truthy(reply.note:find('Every changed hunk', 1, true))

      local ok, err = pcall(tools.run, 'tour_update', { mode = 'insert', steps = { { path = 'c.lua', line = 1 } } })

      eq(false, ok)
      assert.truthy(tostring(err):find('step 1: no file c.lua', 1, true))
    end)

    it('does not claim coverage for files on disk when the range ends somewhere else', function()
      tools.run('tour_scope', { base = base, head = middle })

      local reply = tools.run('tour_start', { title = 'Disk', steps = { { path = 'a.lua', line = 1 } } })

      eq(nil, reply.uncovered)
      eq(nil, reply.note)
    end)
  end)
end)

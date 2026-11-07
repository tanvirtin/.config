local tools = require('nvim_mcp.tools')
local walkthrough_store = require('harness.walkthrough_store')
local walkthrough_tools = require('harness.walkthrough_tools')

local eq = assert.are.same

local SESSION = 's1'

describe('harness.walkthrough_tools:', function()
  local function run(name, args)
    return tools.run(name, args, SESSION)
  end

  before_each(function()
    walkthrough_store.reset()
    walkthrough_tools.register()
  end)

  after_each(function()
    walkthrough_store.reset()
    tools.unregister('walkthrough')
  end)

  it('registers a walkthrough_start tool the agent can read about', function()
    local definition = vim.tbl_filter(function(entry)
      return entry.name == 'walkthrough_start'
    end, tools.definitions())[1]

    assert.truthy(definition)
    assert.truthy(definition.summary:find('Walk the user through', 1, true))
  end)

  it('hands a valid walkthrough to the store and says how many steps it holds', function()
    local seen

    walkthrough_store.on(function(kind, session, walkthrough)
      seen = { kind, session, walkthrough.title, #walkthrough.steps }
    end)

    local result = run('walkthrough_start', {
      title = 'Config',
      steps = { { path = 'init.lua', line = 1, note = 'Start here.' } },
    })

    eq({ 'start', SESSION, 'Config', 1 }, seen)
    eq({ title = 'Config', steps = 1 }, result)
  end)

  it('tells the agent which step has a path that does not exist', function()
    local ok, err = pcall(run, 'walkthrough_start', {
      title = 'Bad',
      steps = { { path = 'init.lua', line = 1 }, { path = 'no/such/file.lua', line = 3 } },
    })

    eq(false, ok)
    assert.truthy(tostring(err):find('step 2: no file no/such/file.lua', 1, true))
    eq(nil, walkthrough_store.current(SESSION))
  end)

  it('ties a walkthrough to the session that asked for it, and keeps sessions apart', function()
    local ok, err = pcall(tools.run, 'walkthrough_start', {
      title = 'Loose',
      steps = { { path = 'init.lua', line = 1 } },
    })

    eq(false, ok)
    assert.truthy(tostring(err):find('a walkthrough belongs to a session', 1, true))

    run('walkthrough_start', { title = 'One', steps = { { path = 'init.lua', line = 1 } } })
    tools.run('walkthrough_start', { title = 'Two', steps = { { path = 'init.lua', line = 1 } } }, 's2')

    eq('One', walkthrough_store.current(SESSION).title)
    eq('Two', walkthrough_store.current('s2').title)

    walkthrough_store.stop(SESSION)

    eq(nil, walkthrough_store.current(SESSION))
    eq('Two', walkthrough_store.current('s2').title)
  end)

  describe('walkthrough_update', function()
    local function start()
      walkthrough_store.start(SESSION, { title = 'Config', steps = { { title = 'one' } } })
    end

    it('passes parsed steps to whoever follows the walkthrough', function()
      local seen

      start()
      walkthrough_store.on(function(kind, _, _, update)
        if kind == 'update' then seen = update end
      end)

      local result = run('walkthrough_update', {
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
      walkthrough_store.on(function(kind, _, _, update)
        if kind == 'update' then seen = update end
      end)
      run('walkthrough_update', { mode = 'note', note = 'Clearer.' })

      eq({ 'note', 'Clearer.' }, { seen.mode, seen.note })
    end)

    it('says what is missing, and that there is no walkthrough to change', function()
      local function message(args)
        return tostring(select(2, pcall(run, 'walkthrough_update', args)))
      end

      assert.truthy(message({ mode = 'note', note = 'x' }):find('no walkthrough is running', 1, true))

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

    it('works the range out from git and hands back the rev to walkthrough', function()
      local scope = run('walkthrough_scope', { base = base, head = middle })

      eq({ base:sub(1, 7), middle:sub(1, 7), middle, false }, { scope.base, scope.head, scope.rev, scope.checked_out })
      eq(
        { 'a.lua', 'b.lua' },
        vim.tbl_map(function(file)
          return file.path
        end, scope.files)
      )
      eq(1, scope.commit_count)
      assert.truthy(scope.next:find('walkthrough_start', 1, true))
    end)

    it('names files relative to a session that runs below the repository root, so its steps resolve', function()
      vim.fn.mkdir(repo .. '/sub', 'p')
      vim.fn.writefile({ 'c1' }, repo .. '/sub/c.lua')
      sh('add', '.')
      sh('commit', '-q', '-m', 'add c')
      vim.cmd('cd ' .. vim.fn.fnameescape(repo .. '/sub'))

      local scope = run('walkthrough_scope', { base = base })
      local paths = vim.tbl_map(function(file)
        return file.path
      end, scope.files)

      eq({ repo .. '/a.lua', repo .. '/b.lua', 'c.lua' }, paths)

      local reply = run('walkthrough_start', { title = 'Review', steps = { { path = 'c.lua', line = 1 } } })

      eq(3, reply.uncovered_count)
      eq(repo .. '/a.lua', reply.uncovered[1].path)
    end)

    it('names a commit that is not here, instead of reviewing nothing', function()
      local ok, err = pcall(run, 'walkthrough_scope', { base = 'nope1234', head = middle })

      eq(false, ok)
      assert.truthy(tostring(err):find('no commit "nope1234"', 1, true))
    end)

    it('walks a commit that is not checked out from git, and says what the steps leave out', function()
      run('walkthrough_scope', { base = base, head = middle })

      local reply = run('walkthrough_start', {
        title = 'Review',
        rev = middle,
        steps = { { path = 'a.lua', line = 2, note = 'a2 changed.' } },
      })
      local walkthrough = walkthrough_store.current(SESSION)

      eq(middle, walkthrough.rev)
      eq(vim.fs.normalize(repo), walkthrough.root)
      eq(2, reply.uncovered_count)
      eq({ 'a.lua', 6, 6 }, { reply.uncovered[1].path, reply.uncovered[1].first, reply.uncovered[1].last })
      assert.truthy(reply.note:find('walkthrough_update', 1, true))
    end)

    it('gives a review walkthrough its base and its uncovered hunks, and takes sections', function()
      run('walkthrough_scope', { base = base, head = middle })

      local reply = run('walkthrough_start', {
        title = 'Review',
        rev = middle,
        steps = {
          { path = 'a.lua', line = 2, title = 'Tests', supporting = true },
          { title = 'Core', ranges = { { path = 'a.lua', line = 6 }, { path = 'b.lua', line = 1, end_line = 2 } } },
        },
      })
      local walkthrough = walkthrough_store.current(SESSION)

      eq(base, walkthrough.base)
      eq({ 'Core', 'Tests' }, { walkthrough.steps[1].title, walkthrough.steps[2].title })
      eq(nil, reply.uncovered)
      eq({}, walkthrough.uncovered)
    end)

    it('says it is complete once every hunk has a step, and checks added steps against the commit', function()
      run('walkthrough_scope', { base = base, head = middle })
      run('walkthrough_start', { title = 'Review', rev = middle, steps = { { path = 'a.lua', line = 2 } } })
      walkthrough_store.on(function(kind, _, walkthrough, update)
        if kind == 'update' then vim.list_extend(walkthrough.steps, update.steps) end
      end)

      local reply = run('walkthrough_update', {
        mode = 'insert',
        steps = { { path = 'a.lua', line = 6 }, { path = 'b.lua', line = 1, end_line = 2 } },
      })

      eq(3, reply.steps)
      eq(nil, reply.uncovered)
      assert.truthy(reply.note:find('Every changed hunk', 1, true))

      local ok, err = pcall(run, 'walkthrough_update', { mode = 'insert', steps = { { path = 'c.lua', line = 1 } } })

      eq(false, ok)
      assert.truthy(tostring(err):find('step 1: no file c.lua', 1, true))
    end)

    it('keeps a review range to the session that worked it out', function()
      run('walkthrough_scope', { base = base, head = middle })

      local reply = tools.run('walkthrough_start', {
        title = 'Elsewhere',
        rev = middle,
        steps = { { path = 'a.lua', line = 2 } },
      }, 's2')

      eq(nil, reply.uncovered)
      eq(nil, reply.note)
    end)

    it('does not claim coverage for files on disk when the range ends somewhere else', function()
      run('walkthrough_scope', { base = base, head = middle })

      local reply = run('walkthrough_start', { title = 'Disk', steps = { { path = 'a.lua', line = 1 } } })

      eq(nil, reply.uncovered)
      eq(nil, reply.note)
    end)
  end)
end)

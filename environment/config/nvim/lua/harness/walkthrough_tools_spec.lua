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

  it('hands a valid walkthrough to the store and replies in one line', function()
    local seen

    walkthrough_store.on(function(kind, session, walkthrough)
      seen = { kind, session, walkthrough.title, #walkthrough.steps }
    end)

    local reply = run('walkthrough_start', { title = 'Config', steps = { { at = { 'init.lua:1' }, note = 'Here.' } } })

    eq({ 'start', SESSION, 'Config', 1 }, seen)
    eq('started "Config" · 1 step', reply)
  end)

  it('tells the agent which step points at a file that does not exist', function()
    local ok, err = pcall(run, 'walkthrough_start', {
      title = 'Bad',
      steps = { { at = { 'init.lua:1' } }, { at = { 'no/such/file.lua:3' } } },
    })

    eq(false, ok)
    assert.truthy(tostring(err):find('step 2: no file no/such/file.lua', 1, true))
    eq(nil, walkthrough_store.current(SESSION))
  end)

  it('ties a walkthrough to the session that asked for it, and keeps sessions apart', function()
    local ok, err = pcall(tools.run, 'walkthrough_start', { title = 'Loose', steps = { { at = { 'init.lua:1' } } } })

    eq(false, ok)
    assert.truthy(tostring(err):find('a walkthrough belongs to a session', 1, true))

    run('walkthrough_start', { title = 'One', steps = { { at = { 'init.lua:1' } } } })
    tools.run('walkthrough_start', { title = 'Two', steps = { { at = { 'init.lua:1' } } } }, 's2')

    eq('One', walkthrough_store.current(SESSION).title)
    eq('Two', walkthrough_store.current('s2').title)

    walkthrough_store.stop(SESSION)

    eq(nil, walkthrough_store.current(SESSION))
    eq('Two', walkthrough_store.current('s2').title)
  end)

  it('names uncovered hunks in runs', function()
    local hunks = vim.tbl_map(function(id)
      return { id = id }
    end, { 'h1', 'h2', 'h3', 'h5', 'h7', 'h8' })

    eq('h1-h3 h5 h7-h8', require('harness.walkthrough_scope').runs(hunks))
  end)

  it('resolves a step\'s findings like its code, and counts them in the reply', function()
    local reply = run('walkthrough_start', {
      title = 'Review',
      steps = {
        {
          at = { 'init.lua:1' },
          findings = { { at = 'init.lua:2', kind = 'suggestion', message = 'Name it.', fix = 'local x = 1' } },
        },
      },
    })
    local finding = walkthrough_store.current(SESSION).steps[1].findings[1]

    eq('started "Review" · 1 step · 1 finding', reply)
    eq({ 2, 'suggestion', { 'local x = 1' } }, { finding.line, finding.kind, finding.fix })

    local ok, err = pcall(run, 'walkthrough_start', {
      title = 'Bad',
      steps = { { at = { 'init.lua:1' }, findings = { { at = 'nope.lua:1', kind = 'issue', message = 'x' } } } },
    })

    eq(false, ok)
    assert.truthy(tostring(err):find('step 1: finding 1: no file nope.lua', 1, true))
  end)

  describe('walkthrough_update', function()
    local function start()
      walkthrough_store.start(SESSION, { title = 'Config', steps = { { title = 'one' } } })
    end

    it('passes resolved steps to whoever follows the walkthrough', function()
      local seen

      start()
      walkthrough_store.on(function(kind, _, _, update)
        if kind == 'update' then seen = update end
      end)

      local reply =
        run('walkthrough_update', { mode = 'insert', steps = { { at = { 'init.lua:2' }, note = 'More.' } } })

      eq('insert', seen.mode)
      eq(1, #seen.steps)
      eq(2, seen.steps[1].line)
      eq('updated "Config" · 1 step', reply)
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
        message({ mode = 'insert', steps = { { at = { 'nope.lua:1' } } } }):find('step 1: no file', 1, true)
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

    it('names files relative to a session that runs below the repository root, so its steps resolve', function()
      vim.fn.mkdir(repo .. '/sub', 'p')
      vim.fn.writefile({ 'c1' }, repo .. '/sub/c.lua')
      sh('add', '.')
      sh('commit', '-q', '-m', 'add c')
      vim.cmd('cd ' .. vim.fn.fnameescape(repo .. '/sub'))

      local text = run('walkthrough_scope', { base = base })

      assert.truthy(text:find('h1 ' .. repo .. '/a.lua:2 +1 -1', 1, true))
      assert.truthy(text:find('h4 c.lua:1 +1 -0', 1, true))

      eq(
        'started "Review" · 1 step\nuncovered: h1-h3 (add with walkthrough_update)',
        run('walkthrough_start', {
          title = 'Review',
          steps = { { at = { 'c.lua:1' } } },
        })
      )
    end)

    it('lists the range in a few lines: commits, then each hunk by id with its diff', function()
      local text = run('walkthrough_scope', { base = base, head = middle })

      eq({
        string.format('%s..%s · 1 commit · 2 files · 3 hunks · +4 -2', base:sub(1, 7), middle:sub(1, 7)),
        middle:sub(1, 7) .. ' change a, add b',
        'h1 a.lua:2 +1 -1',
        '-a2',
        '+A2',
        'h2 a.lua:6 +1 -1',
        '-a6',
        '+A6',
        'h3 b.lua:1-2 +2 -0',
        '+b1',
        '+b2',
        'next: walkthrough_start with steps naming these ids in at',
      }, vim.split(text, '\n', { plain = true }))
    end)

    it('stops the diffs at a budget of characters and says where', function()
      local saved_budget = walkthrough_tools.MAX_DIFF_CHARS

      walkthrough_tools.MAX_DIFF_CHARS = 8

      local text = run('walkthrough_scope', { base = base, head = middle })

      walkthrough_tools.MAX_DIFF_CHARS = saved_budget

      assert.truthy(text:find('h2 a.lua:6 +1 -1\nh3', 1, true))
      assert.truthy(text:find('diffs stop before h2', 1, true))
    end)

    it('cuts a very long changed line short, saying how much it left out', function()
      local saved = walkthrough_tools.MAX_LINE

      walkthrough_tools.MAX_LINE = 2

      local text = run('walkthrough_scope', { base = base, head = middle })

      walkthrough_tools.MAX_LINE = saved

      assert.truthy(text:find('\n-a… (1 more characters)\n', 1, true))
    end)

    it('names a commit that is not here, instead of reviewing nothing', function()
      local ok, err = pcall(run, 'walkthrough_scope', { base = 'nope1234', head = middle })

      eq(false, ok)
      assert.truthy(tostring(err):find('no commit "nope1234"', 1, true))
    end)

    it('walks a commit that is not checked out, from hunk ids, and names the hunks left out', function()
      run('walkthrough_scope', { base = base, head = middle })

      local reply = run('walkthrough_start', { title = 'Review', steps = { { at = { 'h1' }, note = 'a2 changed.' } } })
      local walkthrough = walkthrough_store.current(SESSION)

      eq(middle, walkthrough.rev)
      eq(base, walkthrough.base)
      eq(vim.fs.normalize(repo), walkthrough.root)
      eq({ 2, 2 }, { walkthrough.steps[1].line, walkthrough.steps[1].end_line })
      eq('started "Review" · 1 step\nuncovered: h2-h3 (add with walkthrough_update)', reply)
    end)

    it('takes sections across files and puts supporting steps last', function()
      run('walkthrough_scope', { base = base, head = middle })

      local reply = run('walkthrough_start', {
        title = 'Review',
        steps = {
          { at = { 'h1' }, title = 'Tests', supporting = true },
          { at = { 'h2', 'h3' }, title = 'Core' },
        },
      })
      local walkthrough = walkthrough_store.current(SESSION)

      eq({ 'Core', 'Tests' }, { walkthrough.steps[1].title, walkthrough.steps[2].title })
      eq(2, #walkthrough.steps[1].ranges)
      eq('started "Review" · 2 steps\nevery hunk covered', reply)
      eq({}, walkthrough.uncovered)
    end)

    it('says it is complete once every hunk has a step, and checks added steps against the commit', function()
      run('walkthrough_scope', { base = base, head = middle })
      run('walkthrough_start', { title = 'Review', steps = { { at = { 'h1' } } } })
      walkthrough_store.on(function(kind, _, walkthrough, update)
        if kind == 'update' then vim.list_extend(walkthrough.steps, update.steps) end
      end)

      eq(
        'updated "Review" · 3 steps\nevery hunk covered',
        run('walkthrough_update', { mode = 'insert', steps = { { at = { 'h2' } }, { at = { 'b.lua:1-2' } } } })
      )

      local ok, err = pcall(run, 'walkthrough_update', { mode = 'insert', steps = { { at = { 'c.lua:1' } } } })

      eq(false, ok)
      assert.truthy(tostring(err):find('step 1: no file c.lua', 1, true))
    end)

    it('keeps a review range to the session that worked it out', function()
      run('walkthrough_scope', { base = base, head = middle })

      local ok, err =
        pcall(tools.run, 'walkthrough_start', { title = 'Elsewhere', steps = { { at = { 'h1' } } } }, 's2')

      eq(false, ok)
      assert.truthy(tostring(err):find('call it first', 1, true))
    end)

    it('uses a range once, so a later walkthrough of the code on disk is not taken for a review', function()
      run('walkthrough_scope', { base = base, head = middle })
      run('walkthrough_start', { title = 'Review', steps = { { at = { 'h1' } } } })

      eq('started "Disk" · 1 step', run('walkthrough_start', { title = 'Disk', steps = { { at = { 'a.lua:1' } } } }))
      eq(nil, walkthrough_store.current(SESSION).rev)
    end)
  end)
end)

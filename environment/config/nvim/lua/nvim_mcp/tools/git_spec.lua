local permissions = require('harness.permissions')
local tools = require('nvim_mcp.tools')

local eq = assert.are.same

local function sh(cmd, cwd)
  local out = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert(out.code == 0, table.concat(cmd, ' ') .. ': ' .. (out.stderr or ''))
  return out.stdout
end

local function repo()
  local root = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()

  vim.fn.mkdir(root, 'p')
  root = vim.uv.fs_realpath(root)

  sh({ 'git', 'init', '-q', '-b', 'main' }, root)
  sh({ 'git', 'config', 'user.name', 'Spec Author' }, root)
  sh({ 'git', 'config', 'user.email', 'spec@example.com' }, root)
  vim.fn.writefile({ 'one', 'two', 'three' }, root .. '/a.txt')
  sh({ 'git', 'add', 'a.txt' }, root)
  sh({ 'git', 'commit', '-q', '-m', 'Add a' }, root)

  return root
end

local function run(name, args)
  return tools.run(name, args or {}, 'h1')
end

describe('nvim_mcp.tools.git:', function()
  local cwd, root

  before_each(function()
    tools.register('git', require('nvim_mcp.tools.git'))
    cwd = vim.fn.getcwd()
    root = repo()
    vim.cmd.cd(root)
  end)

  after_each(function()
    vim.cmd.cd(cwd)
    vim.cmd('silent! %bwipeout!')
    tools.unregister('git')
  end)

  it('shows status compactly', function()
    eq('branch main\nclean', run('git_status'))

    vim.fn.writefile({ 'one', 'TWO', 'three' }, root .. '/a.txt')
    vim.fn.writefile({ 'new' }, root .. '/b.txt')

    eq('branch main\nstatus | path\n.M | a.txt\n?? | b.txt', run('git_status'))
  end)

  it('shows the log and blame', function()
    local log = run('git_log')

    assert.is_truthy(log:find('^commit | when | author | subject\n%x+ | .- | Spec Author | Add a$'))

    local blame = run('git_blame', { path = 'a.txt', start_line = 2, end_line = 3 })

    assert.is_truthy(blame:find('2 | %x+ | %d+%-%d+%-%d+ | Spec Author | two'))
    assert.is_truthy(blame:find('3 | ', 1, true))
  end)

  it('shows a diffstat and the patch', function()
    eq('no changes', run('git_diff'))

    vim.fn.writefile({ 'one', 'TWO', 'three' }, root .. '/a.txt')

    local diff = run('git_diff', { path = 'a.txt' })

    assert.is_truthy(diff:find('a.txt | 2 +-', 1, true))
    assert.is_truthy(diff:find('-two\n+TWO', 1, true))
  end)

  it('stages and unstages a whole file', function()
    vim.fn.writefile({ 'one', 'TWO', 'three' }, root .. '/a.txt')

    assert.is_truthy(run('git_stage', { path = 'a.txt' }):find('M. | a.txt', 1, true))
    assert.is_truthy(run('git_stage', { path = 'a.txt', unstage = true }):find('.M | a.txt', 1, true))
    assert.is_truthy(run('git_diff', { staged = true }) == 'no changes')
  end)

  describe('one hunk', function()
    before_each(function()
      vim.fn.writefile({ 'one', 'two', 'three', 'four', 'five' }, root .. '/b.txt')
      sh({ 'git', 'add', 'b.txt' }, root)
      sh({ 'git', 'commit', '-q', '-m', 'Add b' }, root)
      vim.fn.writefile({ 'ONE', 'two', 'three', 'four', 'FIVE' }, root .. '/b.txt')
    end)

    it('stages and unstages just the hunk at a line', function()
      run('git_stage', { path = 'b.txt', line = 5 })

      local staged = run('git_diff', { staged = true })
      assert.is_truthy(staged:find('+FIVE', 1, true))
      assert.is_falsy(staged:find('+ONE', 1, true))
      assert.is_truthy(run('git_status'):find('MM | b.txt', 1, true))

      run('git_stage', { path = 'b.txt', line = 5, unstage = true })
      eq('no changes', run('git_diff', { staged = true }))
    end)

    it('discards just the hunk at a line', function()
      run('git_discard', { path = 'b.txt', line = 1 })

      eq({ 'one', 'two', 'three', 'four', 'FIVE' }, vim.fn.readfile(root .. '/b.txt'))
    end)

    it('says when no hunk touches the line, or the buffer is unsaved', function()
      local ok, err = pcall(run, 'git_stage', { path = 'b.txt', line = 3 })
      eq(false, ok)
      eq('no unstaged hunk at b.txt:3 (git_diff shows them)', err)

      vim.cmd('edit ' .. root .. '/b.txt')
      vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'new' })

      ok, err = pcall(run, 'git_stage', { path = 'b.txt', line = 1 })
      eq(false, ok)
      assert.is_truthy(err:find('unsaved changes; save it first', 1, true))
    end)
  end)

  it('discards a whole file', function()
    vim.fn.writefile({ 'one', 'TWO', 'three' }, root .. '/a.txt')

    eq('branch main\nclean', run('git_discard', { path = 'a.txt' }))
    eq({ 'one', 'two', 'three' }, vim.fn.readfile(root .. '/a.txt'))
  end)

  describe('through vgit', function()
    local calls, finished

    before_each(function()
      calls, finished = {}, false
      package.loaded['vgit'] = {
        run = function(fargs)
          calls[#calls + 1] = fargs

          return vim.async.run(function()
            vim.async.sleep(30)
            if fargs[1] == 'show' then error('bad revision', 0) end
            finished = true
          end)
        end,
      }
    end)

    after_each(function()
      package.loaded['vgit'] = nil
    end)

    it('opens a view and returns once vgit has finished, not after a guess', function()
      local out = run('git_view', { command = 'diff', args = { '--staged', '--', 'a.txt' } })

      eq({ { 'diff', '--staged', '--', 'a.txt' } }, calls)
      eq(true, finished)
      assert.is_truthy(out:find('^opened :VGit diff\n\nmode '))
    end)

    it('reports what vgit failed with', function()
      local ok, err = pcall(run, 'git_view', { command = 'show', args = { 'nope' } })

      eq(false, ok)
      assert.is_truthy(err:find('VGit show: bad revision', 1, true))
    end)
  end)

  it('falls back to the :VGit command when vgit has no run', function()
    local got

    package.loaded['vgit'] = {}
    vim.api.nvim_create_user_command('VGit', function(args)
      got = args.fargs
    end, { nargs = '*' })

    local out = run('git_view', { command = 'diff', args = { '--', 'a.txt' } })

    vim.api.nvim_del_user_command('VGit')
    package.loaded['vgit'] = nil

    eq({ 'diff', '--', 'a.txt' }, got)
    assert.is_truthy(out:find('^opened :VGit diff'))
  end)

  it('says when vgit is missing', function()
    package.loaded['vgit'] = {}
    pcall(vim.api.nvim_del_user_command, 'VGit')

    local ok, err = pcall(run, 'git_view', { command = 'status' })

    package.loaded['vgit'] = nil

    eq(false, ok)
    assert.is_truthy(err:find('require("vgit").run', 1, true))
  end)

  it('refuses to change the repository from git_view', function()
    local ok, err = pcall(run, 'git_view', { command = 'stash', args = { 'drop', '0' } })

    eq(false, ok)
    eq('git stash drop changes the repository; use git_run, which asks the user', err)

    ok, err = pcall(run, 'git_view', { command = 'branch', args = { 'main' } })
    eq(false, ok)
    assert.is_truthy(err:find('git_run', 1, true))
  end)

  it('always asks before discarding, even when exec tools are allowed', function()
    local asked = {}
    local approve = permissions.new({
      auto_allow = true,
      ask = function(request)
        asked[#asked + 1] = request.tool
        return 'allow_always'
      end,
    })
    local function request(tool)
      return { tool = tool, params = { toolCall = { toolCallId = 't' } } }
    end

    eq('allow_once', approve(request('mcp__nvim__git_stage')))
    eq('allow_once', approve(request('mcp__nvim__git_discard')))
    eq('allow_once', approve(request('mcp__nvim__git_discard')))
    eq({ 'mcp__nvim__git_discard', 'mcp__nvim__git_discard' }, asked)
  end)
end)

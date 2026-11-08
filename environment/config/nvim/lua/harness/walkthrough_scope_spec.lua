local walkthrough_scope = require('harness.walkthrough_scope')

local eq = assert.are.same

local function sh(dir, ...)
  local result = vim.system({ 'git', '-C', dir, ... }, { text = true }):wait()

  assert(result.code == 0, result.stderr)

  return vim.trim(result.stdout)
end

describe('harness.walkthrough_scope:', function()
  local dir, first, second, third

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    dir = vim.uv.fs_realpath(dir)
    sh(dir, 'init', '-q', '-b', 'main')
    sh(dir, 'config', 'user.email', 't@example.com')
    sh(dir, 'config', 'user.name', 'T')
    sh(dir, 'config', 'commit.gpgsign', 'false')

    vim.fn.writefile({ 'a1', 'a2', 'a3', 'a4', 'a5', 'a6' }, dir .. '/a.lua')
    sh(dir, 'add', '.')
    sh(dir, 'commit', '-q', '-m', 'start')
    first = sh(dir, 'rev-parse', 'HEAD')

    sh(dir, 'checkout', '-q', '-b', 'feature')
    vim.fn.writefile({ 'a1', 'A2', 'a3', 'a4', 'a5', 'a6', 'a7' }, dir .. '/a.lua')
    vim.fn.writefile({ 'b1', 'b2' }, dir .. '/b.lua')
    sh(dir, 'add', '.')
    sh(dir, 'commit', '-q', '-m', 'second: touch a, add b')
    second = sh(dir, 'rev-parse', 'HEAD')

    vim.fn.writefile({ 'a1', 'A2', 'a3', 'a4', 'a5' }, dir .. '/a.lua')
    os.remove(dir .. '/b.lua')
    sh(dir, 'add', '-A')
    sh(dir, 'commit', '-q', '-m', 'third: trim a, drop b')
    third = sh(dir, 'rev-parse', 'HEAD')
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  it('reads the commits and the changed hunks between two commits', function()
    local scope = assert(walkthrough_scope.compute(dir, first, second))

    eq(
      { 'second: touch a, add b' },
      vim.tbl_map(function(commit)
        return commit.subject
      end, scope.commits)
    )
    eq(
      { 'a.lua', 'b.lua' },
      vim.tbl_map(function(file)
        return file.path
      end, scope.files)
    )
    eq(second, scope.head)
    eq(first, scope.base)
    eq(false, scope.checked_out)

    local a = scope.files[1].hunks

    eq({ 2, 2, 7, 7 }, { a[1].first, a[1].last, a[2].first, a[2].last })
    eq({ 1, 1, 1, 0 }, { a[1].added, a[1].removed, a[2].added, a[2].removed })
    eq({ 1, 2 }, { scope.files[2].hunks[1].first, scope.files[2].hunks[1].last })
    eq(vim.fs.normalize(dir .. '/a.lua'), scope.files[1].absolute)
  end)

  it('defaults to the branch\'s changes against main, ending at what is checked out', function()
    local scope = assert(walkthrough_scope.compute(dir))

    eq(first, scope.base)
    eq(third, scope.head)
    eq(true, scope.checked_out)
    eq(2, #scope.commits)
    eq('third: trim a, drop b', scope.commits[1].subject)
  end)

  it('lists a deleted file without hunks, since it has no lines at the end', function()
    local scope = assert(walkthrough_scope.compute(dir, second, third))

    eq(
      { 'a.lua' },
      vim.tbl_map(function(file)
        return file.path
      end, scope.files)
    )
  end)

  it('numbers every hunk, keeps its changed lines, and names the function it is in', function()
    vim.fn.writefile({ 'local M = {}', '', 'function M.run()', '  return 1', 'end' }, dir .. '/m.lua')
    sh(dir, 'add', '.')
    sh(dir, 'commit', '-q', '-m', 'add m')
    local before = sh(dir, 'rev-parse', 'HEAD')
    vim.fn.writefile({ 'local M = {}', '', 'function M.run()', '  return 2', 'end' }, dir .. '/m.lua')
    sh(dir, 'commit', '-q', '-am', 'change m')

    local scope = assert(walkthrough_scope.compute(dir, before, 'HEAD'))
    local hunk = scope.files[1].hunks[1]

    eq({ 'h1', 4, 4, 'M.run' }, { hunk.id, hunk.first, hunk.last, hunk.symbol })
    eq({ '-  return 1', '+  return 2' }, hunk.lines)
    eq(hunk, scope.by_id.h1.hunk)
  end)

  it('reads a removed line that looks like a file header as a removed line', function()
    local files = walkthrough_scope.parse_diff(table.concat({
      'diff --git a/a.lua b/a.lua',
      '--- a/a.lua',
      '+++ b/a.lua',
      '@@ -1,2 +1 @@',
      '--- a/comment.lua',
      '-+++ b/comment.lua',
      '+kept',
    }, '\n'))

    eq(1, #files)
    eq({ '--- a/comment.lua', '-+++ b/comment.lua', '+kept' }, files[1].hunks[1].lines)
  end)

  it('follows a renamed file to its old path, so it is reviewed as a change and not as all new', function()
    local lines = {}

    for index = 1, 20 do
      lines[index] = 'line ' .. index
    end

    vim.fn.writefile(lines, dir .. '/old.lua')
    sh(dir, 'add', '.')
    sh(dir, 'commit', '-q', '-m', 'add old')
    local before = sh(dir, 'rev-parse', 'HEAD')
    sh(dir, 'mv', 'old.lua', 'new.lua')
    lines[5] = 'changed'
    vim.fn.writefile(lines, dir .. '/new.lua')
    sh(dir, 'commit', '-q', '-am', 'rename')

    local scope = assert(walkthrough_scope.compute(dir, before, 'HEAD'))

    eq({ 'new.lua', 'old.lua', 1 }, { scope.files[1].path, scope.files[1].old_path, #scope.files[1].hunks })
    eq('old.lua', walkthrough_scope.base_path(scope, scope.files[1].absolute))
  end)

  it('has no base path for a file the range adds', function()
    local scope = assert(walkthrough_scope.compute(dir, first, second))

    eq('b.lua', scope.files[2].path)
    eq(nil, walkthrough_scope.base_path(scope, scope.files[2].absolute))
    eq('a.lua', walkthrough_scope.base_path(scope, scope.files[1].absolute))
  end)

  it('lists the files a range deletes', function()
    local scope = assert(walkthrough_scope.compute(dir, second, third))

    eq({ 'b.lua' }, scope.deleted)
  end)

  it('says when a commit does not exist here, instead of guessing', function()
    local scope, err = walkthrough_scope.compute(dir, 'deadbeef00', 'HEAD')

    eq(nil, scope)
    eq('no commit "deadbeef00" in this repository', err)
  end)

  it('asks for a base when there is nothing to compare with', function()
    sh(dir, 'branch', '-m', 'main', 'trunk')

    local scope, err = walkthrough_scope.compute(dir)

    eq(nil, scope)
    assert.truthy(err:find('give a base commit', 1, true))
  end)

  it('finds the hunks no step touches', function()
    local scope = assert(walkthrough_scope.compute(dir, first, second))
    local a = scope.files[1].absolute

    local missing = walkthrough_scope.uncovered(scope, {
      { path = a, line = 1, end_line = 3 },
      { path = scope.files[2].absolute, line = 1, end_line = 1 },
    })

    eq({ { id = 'h2', path = 'a.lua', absolute = a, first = 7, last = 7 } }, missing)
    eq(
      {},
      walkthrough_scope.uncovered(scope, {
        { path = a, line = 2, end_line = 7 },
        { path = scope.files[2].absolute, line = 2, end_line = 2 },
      })
    )
  end)

  it('counts a hunk covered by any range of a step that spans several', function()
    local scope = assert(walkthrough_scope.compute(dir, first, second))

    eq(
      {},
      walkthrough_scope.uncovered(scope, {
        {
          ranges = {
            { path = scope.files[1].absolute, line = 2, end_line = 7 },
            { path = scope.files[2].absolute, line = 2, end_line = 2 },
          },
        },
      })
    )
  end)

  it('lists the hunks one step covers', function()
    local scope = assert(walkthrough_scope.compute(dir, first, second))
    local covered = walkthrough_scope.covered(scope, { path = scope.files[1].absolute, line = 1, end_line = 3 })

    eq({ 'h1' }, { covered[1].id })
    eq(1, #covered)
  end)

  it('reads a file as it was at a commit', function()
    eq({ 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', '' }, walkthrough_scope.show(dir, first, 'a.lua'))
    eq(true, walkthrough_scope.exists_at(dir, second, 'b.lua'))
    eq(false, walkthrough_scope.exists_at(dir, third, 'b.lua'))
  end)
end)

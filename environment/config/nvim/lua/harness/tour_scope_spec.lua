local tour_scope = require('harness.tour_scope')

local eq = assert.are.same

local function sh(dir, ...)
  local result = vim.system({ 'git', '-C', dir, ... }, { text = true }):wait()

  assert(result.code == 0, result.stderr)

  return vim.trim(result.stdout)
end

describe('harness.tour_scope:', function()
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
    local scope = assert(tour_scope.compute(dir, first, second))

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
    local scope = assert(tour_scope.compute(dir))

    eq(first, scope.base)
    eq(third, scope.head)
    eq(true, scope.checked_out)
    eq(2, #scope.commits)
    eq('third: trim a, drop b', scope.commits[1].subject)
  end)

  it('lists a deleted file without hunks, since it has no lines at the end', function()
    local scope = assert(tour_scope.compute(dir, second, third))

    eq(
      { 'a.lua' },
      vim.tbl_map(function(file)
        return file.path
      end, scope.files)
    )
  end)

  it('says when a commit does not exist here, instead of guessing', function()
    local scope, err = tour_scope.compute(dir, 'deadbeef00', 'HEAD')

    eq(nil, scope)
    eq('no commit "deadbeef00" in this repository', err)
  end)

  it('asks for a base when there is nothing to compare with', function()
    sh(dir, 'branch', '-m', 'main', 'trunk')

    local scope, err = tour_scope.compute(dir)

    eq(nil, scope)
    assert.truthy(err:find('give a base commit', 1, true))
  end)

  it('finds the hunks no step touches', function()
    local scope = assert(tour_scope.compute(dir, first, second))
    local a = scope.files[1].absolute

    local missing = tour_scope.uncovered(scope, {
      { path = a, line = 1, end_line = 3 },
      { path = scope.files[2].absolute, line = 1, end_line = 1 },
    })

    eq({ { path = 'a.lua', first = 7, last = 7 } }, missing)
    eq(
      {},
      tour_scope.uncovered(scope, {
        { path = a, line = 2, end_line = 7 },
        { path = scope.files[2].absolute, line = 2, end_line = 2 },
      })
    )
  end)

  it('reads a file as it was at a commit', function()
    eq({ 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', '' }, tour_scope.show(dir, first, 'a.lua'))
    eq(true, tour_scope.exists_at(dir, second, 'b.lua'))
    eq(false, tour_scope.exists_at(dir, third, 'b.lua'))
  end)
end)

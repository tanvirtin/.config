local FileWatch = require('core.FileWatch')

local eq = assert.are.same

describe('core.FileWatch:', function()
  local dir, path, changes, watch

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    path = dir .. '/a.txt'
    vim.fn.writefile({ 'one' }, path)
    changes = 0
    watch = FileWatch(path, {
      debounce_ms = 20,
      on_change = function()
        changes = changes + 1
      end,
    })
  end)

  after_each(function()
    watch:stop()
    vim.fn.delete(dir, 'rf')
  end)

  local function wait_for(n)
    vim.wait(1000, function()
      return changes >= n
    end)
  end

  it('reports a change once, however many writes it was', function()
    watch:start()
    vim.wait(60)

    for i = 1, 4 do
      vim.fn.writefile({ tostring(i) }, path)
    end
    wait_for(1)
    vim.wait(100)

    eq(1, changes)
  end)

  it('catches a write that lands while the watch is still starting', function()
    watch:start()
    vim.fn.writefile({ 'right away' }, path)
    wait_for(1)

    eq(1, changes)
  end)

  it('keeps following a file replaced by rename, again and again', function()
    watch:start()
    vim.wait(60)

    for i = 1, 3 do
      vim.fn.writefile({ 'v' .. i }, path .. '.tmp')
      vim.uv.fs_rename(path .. '.tmp', path)
      wait_for(i)
      eq(i, changes)
    end

    eq(true, watch:is_watching())
  end)

  it('follows a rename that lands while the watch is still starting, and the ones after it', function()
    watch:start()

    for i = 1, 3 do
      vim.fn.writefile({ 'early ' .. i }, path .. '.tmp')
      vim.uv.fs_rename(path .. '.tmp', path)
      wait_for(i)
      eq(i, changes)
    end
  end)

  it('stays quiet once stopped', function()
    watch:start()
    watch:stop()
    vim.fn.writefile({ 'after' }, path)
    vim.wait(150)

    eq(0, changes)
    eq(false, watch:is_watching())
  end)

  it('fingerprints files, and says when one is gone', function()
    local before = FileWatch.fingerprint(path)

    vim.wait(5)
    vim.fn.writefile({ 'changed!' }, path)

    assert.is_true(FileWatch.fingerprint(path) ~= before)
    eq('gone', FileWatch.fingerprint(dir .. '/missing'))
    eq(true, FileWatch.exists(path))
    eq(false, FileWatch.exists(dir))
  end)
end)

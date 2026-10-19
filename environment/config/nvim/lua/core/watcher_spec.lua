local watcher = require('core.watcher')

local eq = assert.are.same

describe('core.watcher:', function()
  it('removes everything it set up on teardown', function()
    watcher.setup()
    watcher.teardown()

    eq(0, watcher.count())
    eq(0, #vim.api.nvim_get_autocmds({ event = 'FileChangedShell' }))
    eq(nil, vim.api.nvim_get_commands({}).DiffDisk)
  end)

  local dir, max

  local function file(name, lines)
    local path = dir .. '/' .. name
    vim.fn.writefile(lines, path)
    return path
  end

  local function edit(path)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    return vim.api.nvim_get_current_buf()
  end

  local function lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  local function settle(ms)
    vim.wait(ms or (watcher.DEBOUNCE_MS * 4))
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    max = watcher.MAX
    watcher.setup()
  end)

  after_each(function()
    watcher.MAX = max
    vim.cmd('silent! %bwipeout!')
    watcher.teardown()
    vim.fn.delete(dir, 'rf')
  end)

  it('reloads a buffer when another program writes its file, without being asked', function()
    local buf = edit(file('a.lua', { 'local a = 1' }))

    eq(true, watcher.is_watching(buf))

    vim.fn.writefile({ 'local a = 2', 'local b = 3' }, dir .. '/a.lua')
    vim.wait(2000, function()
      return lines(buf)[1] == 'local a = 2'
    end)

    eq({ 'local a = 2', 'local b = 3' }, lines(buf))
    eq(false, vim.bo[buf].modified)
  end)

  it('keeps following a file that is replaced by rename, as atomic saves do', function()
    local path = file('b.lua', { 'one' })
    local buf = edit(path)

    for i = 1, 3 do
      local temp = dir .. '/.b.lua.tmp'
      vim.fn.writefile({ 'version ' .. i }, temp)
      vim.uv.fs_rename(temp, path)
      vim.wait(2000, function()
        return lines(buf)[1] == 'version ' .. i
      end)
      eq({ 'version ' .. i }, lines(buf))
    end

    eq(true, watcher.is_watching(buf))
  end)

  it('briefly marks the lines an outside edit changed', function()
    local buf = edit(file('c.lua', { 'a', 'b', 'c' }))

    vim.fn.writefile({ 'a', 'B', 'c' }, dir .. '/c.lua')
    vim.wait(2000, function()
      return lines(buf)[2] == 'B'
    end)

    local marks = vim.api.nvim_buf_get_extmarks(buf, watcher.NAMESPACE, 0, -1, {})

    eq(1, #marks)
    eq(1, marks[1][2])
  end)

  it('never reloads over unsaved changes, and says so once instead of prompting', function()
    local buf = edit(file('d.lua', { 'disk' }))
    local messages = {}
    local notify = vim.notify

    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'mine' })
    vim.fn.writefile({ 'theirs' }, dir .. '/d.lua')
    settle(watcher.DEBOUNCE_MS * 6)
    vim.cmd('checktime')
    vim.cmd('checktime')
    vim.notify = notify

    eq({ 'mine' }, lines(buf))
    eq(1, #messages)
    assert.is_truthy(messages[1]:find('unsaved changes', 1, true))
  end)

  it('compares the buffer with the disk in a new tab', function()
    local buf = edit(file('e.lua', { 'disk' }))
    local tabs = #vim.api.nvim_list_tabpages()

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'mine' })
    watcher.diff_disk(buf)

    eq(tabs + 1, #vim.api.nvim_list_tabpages())
    eq({ 'disk' }, lines(0))
    eq(true, vim.wo.diff)
    vim.cmd('tabclose!')
  end)

  it('never watches chat sessions, scratch buffers or unsaved new files', function()
    local scratch = vim.api.nvim_create_buf(true, true)
    local acwrite = vim.api.nvim_create_buf(true, false)

    vim.bo[acwrite].buftype = 'acwrite'
    vim.api.nvim_buf_set_name(acwrite, dir .. '/composer')

    for _, buf in ipairs({ scratch, acwrite }) do
      watcher.start(buf)
      eq(false, watcher.is_watching(buf))
    end

    vim.cmd('edit ' .. dir .. '/new.lua')
    eq(false, watcher.is_watching(vim.api.nvim_get_current_buf()))

    vim.cmd('write')
    eq(true, watcher.is_watching(vim.api.nvim_get_current_buf()))
  end)

  it('leaves no watcher behind when a buffer is unloaded, deleted or wiped', function()
    local before = watcher.count()
    local a = edit(file('f.lua', { 'f' }))
    local b = edit(file('g.lua', { 'g' }))
    local c = edit(file('h.lua', { 'h' }))

    eq(before + 3, watcher.count())

    vim.cmd('enew')
    vim.cmd('bunload ' .. a)
    vim.cmd('bdelete ' .. b)
    vim.cmd('bwipeout ' .. c)

    eq(before, watcher.count())
    eq({ false, false, false }, { watcher.is_watching(a), watcher.is_watching(b), watcher.is_watching(c) })
  end)

  it('follows a buffer renamed with :saveas', function()
    local buf = edit(file('i.lua', { 'i' }))

    vim.cmd('saveas ' .. dir .. '/renamed.lua')
    vim.fn.writefile({ 'changed' }, dir .. '/renamed.lua')
    vim.wait(2000, function()
      return lines(buf)[1] == 'changed'
    end)

    eq({ 'changed' }, lines(buf))
  end)

  it('caps how many files it watches, dropping the least recently used', function()
    watcher.stop_all()
    watcher.MAX = 3

    local bufs = {}

    for i = 1, 5 do
      bufs[i] = edit(file('cap' .. i .. '.lua', { tostring(i) }))
    end

    eq(3, watcher.count())
    eq({ false, false, true, true, true }, vim.tbl_map(watcher.is_watching, bufs))

    vim.cmd('buffer ' .. bufs[1])

    eq(3, watcher.count())
    eq(true, watcher.is_watching(bufs[1]))
    eq(false, watcher.is_watching(bufs[3]))
  end)

  it('stops watching a file that was deleted, and says so', function()
    local buf = edit(file('j.lua', { 'j' }))
    local messages = {}
    local notify = vim.notify

    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end

    vim.fn.delete(dir .. '/j.lua')
    vim.wait(2000, function()
      return not watcher.is_watching(buf)
    end)
    vim.notify = notify

    eq(false, watcher.is_watching(buf))
    eq({ 'j' }, lines(buf))
    assert.is_truthy(messages[1] and messages[1]:find('deleted', 1, true))
  end)
end)

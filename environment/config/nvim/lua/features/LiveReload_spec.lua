local Buffer = require('core.Buffer')
local LiveReload = require('features.LiveReload')

local eq = assert.are.same

describe('features.LiveReload:', function()
  local live
  it('removes everything it set up on cleanup', function()
    local before = #vim.api.nvim_get_autocmds({ event = 'FileChangedShell' })
    local other = LiveReload():register_events()

    eq(before + 1, #vim.api.nvim_get_autocmds({ event = 'FileChangedShell' }))
    other:cleanup()

    eq(0, other:count())
    eq(before, #vim.api.nvim_get_autocmds({ event = 'FileChangedShell' }))
    eq(nil, vim.api.nvim_get_commands({}).DiffDisk)
  end)

  local dir

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
    vim.wait(ms or (LiveReload.DEBOUNCE_MS * 4))
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    live = LiveReload():register_events()
  end)

  after_each(function()
    vim.cmd('silent! %bwipeout!')
    live:cleanup()
    vim.fn.delete(dir, 'rf')
  end)

  it('reloads a buffer when another program writes its file, without being asked', function()
    local buf = edit(file('a.lua', { 'local a = 1' }))

    eq(true, live:is_watching(Buffer(buf)))

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

    eq(true, live:is_watching(Buffer(buf)))
  end)

  it('briefly marks the lines an outside edit changed', function()
    local buf = edit(file('c.lua', { 'a', 'b', 'c' }))

    vim.fn.writefile({ 'a', 'B', 'c' }, dir .. '/c.lua')
    vim.wait(2000, function()
      return lines(buf)[2] == 'B'
    end)

    local marks = vim.api.nvim_buf_get_extmarks(buf, LiveReload.NAMESPACE, 0, -1, {})

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
    settle(LiveReload.DEBOUNCE_MS * 6)
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
    live:diff_disk(Buffer(buf))

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
      live:start(Buffer(buf))
      eq(false, live:is_watching(Buffer(buf)))
    end

    vim.cmd('edit ' .. dir .. '/new.lua')
    eq(false, live:is_watching(Buffer(0)))

    vim.cmd('write')
    eq(true, live:is_watching(Buffer(0)))
  end)

  it('leaves no watch behind when a buffer is unloaded, deleted or wiped', function()
    local before = live:count()
    local a = edit(file('f.lua', { 'f' }))
    local b = edit(file('g.lua', { 'g' }))
    local c = edit(file('h.lua', { 'h' }))

    eq(before + 3, live:count())

    vim.cmd('enew')
    vim.cmd('bunload ' .. a)
    vim.cmd('bdelete ' .. b)
    vim.cmd('bwipeout ' .. c)

    eq(before, live:count())
    eq(
      { false, false, false },
      { live:is_watching(Buffer(a)), live:is_watching(Buffer(b)), live:is_watching(Buffer(c)) }
    )
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
    live:stop_all()
    live.max = 3

    local bufs = {}

    for i = 1, 5 do
      bufs[i] = edit(file('cap' .. i .. '.lua', { tostring(i) }))
    end

    eq(3, live:count())
    eq(
      { false, false, true, true, true },
      vim.tbl_map(function(b)
        return live:is_watching(Buffer(b))
      end, bufs)
    )

    vim.cmd('buffer ' .. bufs[1])

    eq(3, live:count())
    eq(true, live:is_watching(Buffer(bufs[1])))
    eq(false, live:is_watching(Buffer(bufs[3])))
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
      return not live:is_watching(Buffer(buf))
    end)
    vim.notify = notify

    eq(false, live:is_watching(Buffer(buf)))
    eq({ 'j' }, lines(buf))
    assert.is_truthy(messages[1] and messages[1]:find('deleted', 1, true))
  end)
end)

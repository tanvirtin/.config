local Connection = require('harness.servers.acp.Connection')
local Session = require('harness.Session')
local Window = require('core.Window')
local display = require('harness.ui.display')
local docks = require('harness.ui.docks')
local fake_agent = require('harness.servers.acp.fake_agent')

local eq = assert.are.same

local function session()
  return Session({
    key = 'h' .. math.random(1e6),
    id = 's' .. math.random(1e6),
    connection = Connection(fake_agent.new()),
  })
end

local function tiled(tab)
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ''
  end, vim.api.nvim_tabpage_list_wins(tab or 0))
end

local function name(win)
  return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
end

describe('harness.ui.docks:', function()
  local first, code

  before_each(function()
    docks.reset()
    docks.register_events()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.wo.winfixbuf = false
    vim.wo.winfixwidth = false
    vim.cmd('enew!')
    code = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(code, 0, -1, false, { 'code' })
    first = session()
  end)

  after_each(function()
    docks.reset()
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.wo.winfixbuf = false
    vim.wo.winfixwidth = false
    vim.cmd('enew!')
  end)

  local function view_of(s)
    display.open(s, { background = true })

    return display.view_of(s)
  end

  it('docks a session on the right at the compact width, leaving the code where it was', function()
    local code_win = vim.api.nvim_get_current_win()
    local view = view_of(first)

    eq(true, docks.run('', view))

    local dock = docks.open_dock()

    eq(true, dock:is_open())
    eq(view.bufnr, vim.api.nvim_win_get_buf(dock.window.win_id))
    eq(2, #tiled())
    eq(code, vim.api.nvim_win_get_buf(code_win))
    eq(math.max(40, math.floor(vim.o.columns * 0.3)), dock.window:get_width())
    assert.is_true(vim.api.nvim_win_get_position(dock.window.win_id)[2] > vim.api.nvim_win_get_position(code_win)[2])
  end)

  it('keeps nothing but the harness in it: other buffers are refused, the dock switches sessions itself', function()
    local view = view_of(first)
    local other = view_of(session())

    docks.run('', view)

    local dock = docks.open_dock()
    local win = dock.window.win_id

    eq(true, vim.wo[win].winfixbuf)
    eq(true, vim.wo[win].winfixwidth)

    vim.api.nvim_set_current_win(win)
    assert.is_false(pcall(vim.cmd, 'enew'))
    assert.is_false(pcall(vim.api.nvim_win_set_buf, win, code))
    eq(view.bufnr, vim.api.nvim_win_get_buf(win))

    dock:show(other)
    eq(other.bufnr, vim.api.nvim_win_get_buf(win))
    eq(true, vim.wo[win].winfixbuf)
  end)

  it('cycles compact, half, a zoom tab of its own, and back to compact', function()
    local origin = vim.api.nvim_get_current_tabpage()
    local view = view_of(first)

    docks.run('', view)

    local dock = docks.open_dock()

    docks.run('', view)
    eq(math.max(40, math.floor(vim.o.columns * 0.5)), dock.window:get_width())

    docks.run('', view)
    eq(2, #vim.api.nvim_list_tabpages())
    assert.are_not.equal(origin, vim.api.nvim_get_current_tabpage())
    eq(view.bufnr, vim.api.nvim_win_get_buf(0))
    eq(1, #tiled())
    eq(true, vim.wo.winfixbuf)
    eq(false, dock:is_open())
    eq(code, vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_list_wins(origin)[1]))

    docks.run('', view)
    eq(origin, vim.api.nvim_get_current_tabpage())
    eq(1, #vim.api.nvim_list_tabpages())
    eq(true, dock:is_open())
    eq(math.max(40, math.floor(vim.o.columns * 0.3)), dock.window:get_width())
    eq(2, #tiled())
  end)

  it('comes back to the origin tab and its dock when the zoom tab is closed another way', function()
    local origin = vim.api.nvim_get_current_tabpage()
    local view = view_of(first)

    docks.run('zoom', view)
    eq(2, #vim.api.nvim_list_tabpages())

    vim.cmd('quit')
    vim.wait(300, function()
      return docks.open_dock(origin) ~= nil
    end)

    eq(origin, vim.api.nvim_get_current_tabpage())
    eq(true, docks.open_dock(origin):is_open())
    eq(1, #vim.api.nvim_list_tabpages())
  end)

  it('remembers a width you dragged, and reopens at it', function()
    local view = view_of(first)

    docks.run('', view)

    local dock = docks.open_dock()

    dock.window:set_width(70)
    vim.api.nvim_exec_autocmds('WinResized', {})
    docks.run('close', view)
    eq(false, dock:is_open())

    docks.run('open', view)
    eq(true, docks.open_dock():is_open())
  end)

  it('opens a session into the dock instead of a window of its own', function()
    local view = view_of(first)
    local other = session()

    docks.run('', view)

    local dock = docks.open_dock()
    local before = #tiled()

    display.open(other)

    eq(before, #tiled())
    eq(display.buffer_of(other), vim.api.nvim_win_get_buf(dock.window.win_id))
    eq(dock.window.win_id, vim.api.nvim_get_current_win())
    eq(other, display.last().session)
  end)

  it('puts the transcript it docks back to the code it was open over', function()
    local view = view_of(first)
    local win = vim.api.nvim_get_current_win()

    view.source_buf = code
    view:show_in(Window(win))
    eq(view.bufnr, vim.api.nvim_win_get_buf(win))

    docks.run('', view)

    eq(code, vim.api.nvim_win_get_buf(win))
    eq(1, #vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_buf(w) == view.bufnr
    end, vim.api.nvim_tabpage_list_wins(0)))
  end)

  it('closes with the window, and a fresh one is made when asked again', function()
    local view = view_of(first)

    docks.run('', view)

    local dock = docks.open_dock()

    vim.api.nvim_win_close(dock.window.win_id, true)
    eq(false, dock:is_open())
    assert.is_nil(docks.open_dock())

    docks.run('', view)
    eq(true, docks.open_dock():is_open())
  end)

  it('has a dock per tab', function()
    local view = view_of(first)

    docks.run('', view)

    local here = docks.open_dock()

    vim.cmd('tabnew')
    assert.is_nil(docks.open_dock())

    docks.run('', view)

    local there = docks.open_dock()

    assert.are_not.equal(here, there)
    eq(true, here:is_open())
  end)

  it('says so when there is no session to dock, and what it accepts', function()
    eq({ false, docks.NO_SESSION }, { docks.run('', nil) })
    assert.is_false((docks.run('sideways', nil)))
  end)

  it('lets a composer open under the dock, as wide as it', function()
    local composer = require('harness.ui.composer')
    local view = view_of(first)

    docks.run('', view)

    local dock = docks.open_dock()

    vim.api.nvim_set_current_win(dock.window.win_id)
    composer.open(first, { display = display })

    local win = vim.tbl_filter(function(w)
      return name(w):find('harness://composer', 1, true) ~= nil
    end, vim.api.nvim_tabpage_list_wins(0))[1]

    eq(dock.window:get_width(), vim.api.nvim_win_get_width(win))
    composer.close(true)
  end)
end)

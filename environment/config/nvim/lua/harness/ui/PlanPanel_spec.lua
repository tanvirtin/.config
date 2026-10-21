local PlanPanel = require('harness.ui.PlanPanel')
local Window = require('core.Window')

local eq = assert.are.same

local function history(statuses)
  local entries = {}

  for i, status in ipairs(statuses) do
    entries[i] = { content = 'step ' .. i, status = status }
  end

  return { { kind = 'plan', entries = entries } }
end

local function floats()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative ~= ''
  end, vim.api.nvim_tabpage_list_wins(0))
end

describe('harness.ui.PlanPanel:', function()
  local panel, window

  before_each(function()
    vim.cmd('silent! only!')
    panel = PlanPanel()
    window = Window.get_current()
  end)

  after_each(function()
    panel:hide()
  end)

  it('floats an open plan at the top right of the window', function()
    panel:update(history({ 'completed', 'pending' }), window)

    local wins = floats()

    eq(1, #wins)

    local config = vim.api.nvim_win_get_config(wins[1])

    eq({ 'win', window.win_id, 'NE' }, { config.relative, config.win, config.anchor })
    eq(' Plan  1/2', vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, 1, false)[1])
  end)

  it('hides once every entry is done, or there is no plan', function()
    panel:update(history({ 'pending' }), window)
    panel:update(history({ 'completed' }), window)

    eq(0, #floats())

    panel:update({}, window)
    eq(0, #floats())
  end)

  it('toggles: hiding an open plan keeps it hidden, showing a finished one keeps it shown', function()
    panel:update(history({ 'pending' }), window)
    panel:toggle(history({ 'pending' }), window)
    panel:update(history({ 'pending' }), window)

    eq(0, #floats())

    panel:toggle(history({ 'completed' }), window)
    panel:update(history({ 'completed' }), window)

    eq(1, #floats())
  end)

  it('repaints when the plan changes, in the same window', function()
    panel:update(history({ 'pending', 'pending' }), window)

    local win = floats()[1]

    panel:update(history({ 'completed', 'pending' }), window)

    eq({ win }, floats())
    eq(' Plan  1/2', vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1])
  end)
end)

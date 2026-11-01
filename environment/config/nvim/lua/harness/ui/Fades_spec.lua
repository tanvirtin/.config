local Buffer = require('core.Buffer')
local Fades = require('harness.ui.Fades')

local eq = assert.are.same

describe('harness.ui.Fades:', function()
  local buffer, fades

  before_each(function()
    buffer = Buffer():create(false, true)
    buffer:set_lines({ 'a', 'b', 'c', 'd' })
    fades = Fades(buffer)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buffer.bufnr, { force = true })
  end)

  local function marks()
    return vim.tbl_map(function(mark)
      return { mark[2], mark[4].end_row, mark[4].hl_group }
    end, buffer:get_extmarks(Fades.NAMESPACE, 0, -1, { details = true }))
  end

  it('starts new rows dimmed and eases them to full, then leaves them alone', function()
    eq(true, fades:touch(1, 2, 1000))
    eq(true, fades:step(1000))
    eq({ { 1, 3, 'UiFade1' } }, marks())

    fades:step(1100)

    local mid = tonumber(marks()[1][3]:match('%d+$'))

    assert.is_true(mid > 1)
    eq(false, fades:step(1200))
    eq({}, marks())
  end)

  it('does not fade a rewrite of the whole transcript', function()
    eq(false, fades:touch(0, 500, 0))
    eq(false, fades:step(0))
  end)

  it('keeps separate chunks fading on their own clocks', function()
    fades:touch(0, 0, 1000)
    fades:touch(2, 3, 1100)
    fades:step(1120)

    eq(2, #marks())
  end)
end)

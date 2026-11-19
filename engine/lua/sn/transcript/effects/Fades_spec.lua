local Buffer = require('core.editor.Buffer')
local Fades = require('sn.transcript.effects.Fades')

local eq = assert.are.same

describe('sn.transcript.effects.Fades:', function()
  local buffer, fades

  before_each(function()
    buffer = Buffer():create(false, true)
    buffer:set_lines({ 'a', 'b', 'c', 'd' })
    fades = Fades(buffer)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buffer.bufnr, { force = true })
  end)

  local function details(overlay)
    return vim.tbl_filter(function(mark)
      return (mark[4].virt_text_pos == 'overlay') == (overlay == true)
    end, buffer:get_extmarks(Fades.NAMESPACE, 0, -1, { details = true }))
  end

  local function marks()
    return vim.tbl_map(function(mark)
      return { mark[2], mark[4].end_row, mark[4].hl_group }
    end, details())
  end

  local function spans()
    return vim.tbl_map(function(mark)
      return { mark[2], mark[3], mark[4].hl_group }
    end, details())
  end

  local function view_of(kind)
    return {
      document = {
        block_at = function()
          return { kind = kind }
        end,
      },
    }
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

  it('fades each streamed row once, instead of restarting the fade on the rewritten tail', function()
    eq(true, fades:touch(1, 2, 1000))
    eq(true, fades:touch(2, 3, 1010))
    eq(false, fades:touch(1, 3, 1020))

    fades:step(1020)

    local rows = vim.tbl_map(function(mark)
      return mark[2]
    end, buffer:get_extmarks(Fades.NAMESPACE, 0, -1))

    eq({ 1, 3 }, rows)
  end)

  it('fades a thought toward its own dim colour, so streamed lines never flash brighter than the block', function()
    fades = Fades(buffer, view_of('thought'))

    eq(true, fades:touch(1, 2, 1000))
    fades:step(1000)

    eq({ { 1, 3, 'UiThoughtStream1' } }, marks())
  end)

  it('tunes a streamed thought in out of static, then leaves the text clear', function()
    buffer:set_lines({ '> [!thought]', '> planning the next careful step', 'c', 'd' })
    fades = Fades(buffer, view_of('thought'))

    fades:touch(1, 1, 1000)
    fades:step(1000)

    local early = details(true)

    assert.is_true(#early > 0)

    for _, mark in ipairs(early) do
      eq(1, mark[2])
      assert.is_true(mark[3] >= 2)
    end

    fades:step(1100)
    eq({}, details(true))
  end)

  it('keeps plain message text free of static while it fades in', function()
    buffer:set_lines({ 'a', 'planning the next careful step', 'c', 'd' })

    fades:touch(1, 1, 1000)
    fades:step(1000)

    eq({}, details(true))
  end)

  it('dissolves only the text appended to a row that is already on screen', function()
    fades:remember(1, 1)

    buffer:set_lines({ 'a', 'bcd', 'c', 'd' })

    eq(1, fades:grown(1))
    eq(true, fades:touch(1, 1, 1000, nil, fades:grown(1)))

    fades:step(1000)

    eq({ { 1, 1, 'UiFade1' } }, spans())
  end)

  it('restarts the dissolve on the appended text instead of dimming the whole line again', function()
    fades:remember(1, 1)
    fades:touch(1, 1, 1000)

    buffer:set_lines({ 'a', 'bcd', 'c', 'd' })

    eq(true, fades:touch(1, 1, 1010, nil, fades:grown(1)))
    fades:step(1010)

    eq({ { 1, 1, 'UiFade1' } }, spans())
  end)

  it('leaves a row alone when it was rewritten rather than appended to', function()
    fades:remember(1, 1)

    buffer:set_lines({ 'a', 'zzz', 'c', 'd' })

    assert.is_nil(fades:grown(1))
  end)
end)

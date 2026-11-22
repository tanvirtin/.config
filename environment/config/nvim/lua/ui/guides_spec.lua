local guides = require('ui.guides')
local Buffer = require('core.editor.Buffer')

local eq = assert.are.same

describe('ui.guides:', function()
  local buffer

  local function marks()
    return buffer:get_extmarks(guides.NAMESPACE, 0, -1, { details = true })
  end

  before_each(function()
    buffer = Buffer(vim.api.nvim_create_buf(false, true))
    buffer:set_lines({ 'a', 'b', 'c', 'd' })
  end)

  after_each(function()
    guides.clear('s1')
    guides.clear('s2')
    vim.api.nvim_buf_delete(buffer.bufnr, { force = true })
  end)

  local function above(mark)
    eq(true, mark[4].virt_lines_above)
    return mark[4].virt_lines
  end

  it('should draw the note above the line, numbered for a step, without tinting the code', function()
    guides.mark('s1', buffer, { from = 2, to = 3, step = 1, label = 'entry' })

    local mark = marks()[1]

    eq(1, mark[2])
    eq(nil, mark[4].hl_group)
    eq({ { { ' 1. entry ', guides.HL } } }, above(mark))
  end)

  it('should bullet a note with no step and indent it like the code', function()
    vim.bo[buffer.bufnr].tabstop = 4
    buffer:set_lines({ '\t  x' })

    guides.mark('s1', buffer, { from = 1, label = 'here' })

    eq({ { { '     ' }, { ' - here ', guides.HL } } }, above(marks()[1]))
  end)

  it('should put the icon on a line of its own above the note, both in one band', function()
    guides.set_icon(function()
      return { { 'ICON', 'Group' } }
    end)

    guides.mark('s1', buffer, { from = 1, label = 'longer' })
    guides.set_icon(nil)

    eq({
      { { ' ', guides.HL }, { 'ICON', { guides.HL, 'Group' } }, { string.rep(' ', 5), guides.HL } },
      { { ' - longer ', guides.HL } },
    }, above(marks()[1]))
  end)

  it('should draw the note alone when the provider has no icon', function()
    guides.set_icon(function()
      return nil
    end)

    guides.mark('s1', buffer, { from = 1, label = 'x' })
    guides.set_icon(nil)

    eq({ { { ' - x ', guides.HL } } }, above(marks()[1]))
  end)

  describe('jump', function()
    local Window = require('core.editor.Window')
    local window

    before_each(function()
      window = Window.get_current()
      window:set_buffer(buffer)
      window:set_cursor({ 1, 0 })
    end)

    it('should move to the next and previous guide, wrapping around', function()
      guides.mark('s1', buffer, { from = 2, step = 1 })
      guides.mark('s2', buffer, { from = 4, step = 2 })

      eq(2, guides.jump(window, 1))
      eq(4, guides.jump(window, 1))
      eq(2, guides.jump(window, 1))
      eq(4, guides.jump(window, -1))
      eq(2, guides.jump(window, -1))
      eq(2, window:get_cursor()[1])
    end)

    it('should stay put when the buffer has no guides', function()
      eq(nil, guides.jump(window, 1))
      eq(1, window:get_cursor()[1])
    end)
  end)

  it('should place nothing without a label or a step', function()
    eq(nil, guides.mark('s1', buffer, { from = 1 }))
    eq(0, #marks())
  end)

  it('should clamp a line past the end of the buffer', function()
    guides.mark('s1', buffer, { from = 99, step = 2 })

    eq(3, marks()[1][2])
  end)

  it('should count an owner\'s guides without copying them', function()
    eq(0, guides.count('s1'))

    guides.mark('s1', buffer, { from = 1, step = 1 })
    guides.mark('s1', buffer, { from = 2, step = 2 })
    guides.mark('s2', buffer, { from = 3, step = 1 })

    eq(2, guides.count('s1'))
    eq(1, guides.count('s2'))
  end)

  it('should clear only the owner\'s guides', function()
    guides.mark('s1', buffer, { from = 1, step = 1 })
    guides.mark('s2', buffer, { from = 2, step = 1 })

    eq(1, guides.clear('s1'))
    eq(1, #marks())
    eq(1, #guides.list('s2'))
  end)

  it('should clear one buffer and keep the rest', function()
    local other = Buffer(vim.api.nvim_create_buf(false, true))
    other:set_lines({ 'x' })

    guides.mark('s1', buffer, { from = 1, step = 1 })
    guides.mark('s1', other, { from = 1, step = 2 })

    eq(1, guides.clear('s1', other))
    eq(1, #guides.list('s1'))

    vim.api.nvim_buf_delete(other.bufnr, { force = true })
  end)
end)

local Lens = require('ui.Lens')
local Window = require('core.editor.Window')

local HEIGHT = 5
local ROWS = HEIGHT + Lens.CHROME_ROWS

local eq = assert.are.same

describe('ui.Lens:', function()
  local columns, lines, window, buffer, height

  local function marks()
    return buffer:get_extmarks(Lens.NAMESPACE, 0, -1, { details = true })
  end

  before_each(function()
    columns, lines = vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 120, 40
    vim.cmd('silent! tabonly!')
    vim.cmd('silent! only!')
    vim.cmd('enew!')

    window = Window.get_current()
    buffer = window:get_buffer()
    height = HEIGHT

    local text = {}

    for i = 1, 100 do
      text[i] = 'line ' .. i
    end

    buffer:set_lines(text)
    vim.wo.scrolloff = 0
  end)

  after_each(function()
    buffer:clear_namespace(Lens.NAMESPACE)
    vim.o.columns, vim.o.lines = columns, lines
  end)

  describe('fits', function()
    it('should accept a roomy window on a file buffer', function()
      eq(true, Lens.fits(window, ROWS))
    end)

    it('should refuse a window too short for the rows and some code around them', function()
      vim.o.lines = 8

      eq(false, Lens.fits(window, ROWS))
      eq(true, Lens.fits(window, 2))
    end)

    it('should refuse a narrow window', function()
      vim.o.columns = Lens.MIN_WIDTH - 5

      eq(false, Lens.fits(window, ROWS))
    end)

    it('should refuse a floating window and a buffer that is not a file', function()
      local scratch = vim.api.nvim_create_buf(false, true)
      local float =
        vim.api.nvim_open_win(scratch, false, { relative = 'editor', row = 1, col = 1, width = 80, height = 20 })

      eq(false, Lens.fits(Window(float), ROWS))

      vim.bo[buffer.bufnr].buftype = 'nofile'
      eq(false, Lens.fits(window, ROWS))
      vim.bo[buffer.bufnr].buftype = ''
      vim.api.nvim_win_close(float, true)
    end)
  end)

  describe('reserve', function()
    it('should put blank virtual lines above the cursor line and anchor the float just over them', function()
      local inline = Lens(window, 20):reserve(height)
      local mark = marks()[1]

      eq(19, mark[2])
      eq(true, mark[4].virt_lines_above)
      eq(height + Lens.CHROME_ROWS, #mark[4].virt_lines)
      eq('above', inline.side)

      local config = inline:config()

      eq('SW', config.anchor)
      eq({ 19, 0 }, config.bufpos)
      eq(0, config.row)
      eq(window.win_id, config.win)
    end)

    it('should scroll one line so the blank lines are not hidden at the top of the window', function()
      window:call(function()
        vim.cmd('normal! 30Gzt')
      end)
      eq(30, window:get_view().topline)

      local inline = Lens(window, 30):reserve(height)

      eq('above', inline.side)
      assert.is_true(window:get_view().topline < 30)
    end)

    it('should open below the first line, under the header row, where there is nothing above', function()
      local inline = Lens(window, 1):reserve(height)
      local config = inline:config()

      eq('below', inline.side)
      eq(false, marks()[1][4].virt_lines_above)
      eq({ 'NW', 1 + Lens.CHROME_ROWS }, { config.anchor, config.row })
    end)

    it('should draw a header as the first reserved row, keeping the room the same size', function()
      local inline = Lens(window, 20):reserve(height)

      inline:header({ { ' h1 ', 'UiTitle' } })

      local lines = marks()[1][4].virt_lines

      eq(1, #marks())
      eq({ { ' h1 ', 'UiTitle' } }, lines[1])
      eq(height + Lens.CHROME_ROWS, #lines)
      eq(19, marks()[1][2])
    end)

    it('should keep the header when the line moves', function()
      local inline = Lens(window, 20):reserve(height)

      inline:header({ { ' h1 ' } })
      vim.api.nvim_buf_set_lines(buffer.bufnr, 0, 0, false, { 'a', 'b' })
      inline:header({ { ' h2 ' } })

      eq(1, #marks())
      eq(21, marks()[1][2])
      eq({ { ' h2 ' } }, marks()[1][4].virt_lines[1])
    end)

    it('should start at the text, which the anchor cell already sits at, and end at the window edge', function()
      vim.wo.number = true

      local config = Lens(window, 20):reserve(height):config()

      eq(0, config.col)
      eq(window:get_text_width(), config.width)
    end)
  end)

  describe('following', function()
    it('should follow its line when text is inserted above it', function()
      local inline = Lens(window, 20):reserve(height)

      vim.api.nvim_buf_set_lines(buffer.bufnr, 0, 0, false, { 'a', 'b', 'c' })

      eq(23, inline:current())
      eq({ 22, 0 }, inline:config().bufpos)
      eq({ win = window.win_id, line = 23 }, inline:request())
      eq(true, inline:matches({ win = window.win_id, line = 23 }))
      eq(false, inline:matches({ win = window.win_id, line = 20 }))
    end)

    it('should give the room back when released', function()
      local inline = Lens(window, 20):reserve(height)

      inline:release()

      eq(0, #marks())
      eq(20, inline:current())
    end)

    it('should leave when the window it sits in closes, and clean up when disposed', function()
      vim.cmd('vsplit')

      local host = Window.get_current()
      local left = 0
      local inline = Lens(host, 5):reserve(height)
      local follow = inline:follow('spec', {
        is_valid = function()
          return false
        end,
      }, function()
        left = left + 1
      end)

      host:close()
      vim.wait(50, function()
        return left > 0
      end)

      eq(1, left)

      follow.dispose()
      eq(0, #marks())
    end)

    it('should leave when another buffer takes its window', function()
      local left = 0
      local inline = Lens(window, 5):reserve(height)
      local follow = inline:follow('spec', {
        is_valid = function()
          return false
        end,
      }, function()
        left = left + 1
      end)

      vim.cmd('enew')
      vim.wait(50, function()
        return left > 0
      end)

      assert.is_true(left >= 1)
      follow.dispose()
    end)
  end)
end)

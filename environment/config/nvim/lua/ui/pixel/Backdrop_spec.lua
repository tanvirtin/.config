local Window = require('core.Window')
local graphics = require('core.graphics')
local Backdrop = require('ui.pixel.Backdrop')

local eq = assert.are.same

local RED = { 255, 0, 0 }

local function fill(bitmap, size)
  bitmap:rect(0, 0, size.width, size.height, RED, 1)
end

local function alpha(bytes, width, x, y)
  return bytes:byte((y * width + x) * 4 + 4)
end

describe('ui.pixel.Backdrop:', function()
  local drawn, deleted, floats, backdrops, original

  local function float(opts)
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(
      buf,
      false,
      vim.tbl_extend('force', { relative = 'editor', row = 2, col = 2, width = 20, height = 8 }, opts)
    )

    floats[#floats + 1] = win

    return win
  end

  local function backdrop_for(win_id)
    local backdrop = Backdrop({ window = Window(win_id), draw = fill })

    backdrops[#backdrops + 1] = backdrop

    return backdrop
  end

  before_each(function()
    drawn, deleted, floats, backdrops = {}, {}, {}, {}
    original = { draw = graphics.draw, delete = graphics.delete, supported = graphics.supported }
    graphics.supported = function()
      return true
    end
    graphics.draw = function(id, bytes, width, height, place, replaced)
      drawn[#drawn + 1] = { id = id, bytes = bytes, width = width, height = height, place = place, replaced = replaced }
    end
    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end
  end)

  after_each(function()
    for _, backdrop in ipairs(backdrops) do
      backdrop:destroy()
    end

    for _, win in ipairs(floats) do
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end

    vim.wait(10, function()
      return false
    end)

    graphics.draw, graphics.delete, graphics.supported = original.draw, original.delete, original.supported
  end)

  it('places the image at the outer box of its window, behind the text', function()
    local backdrop = backdrop_for(float({ row = 2, col = 2, width = 20, height = 8, border = 'rounded' }))

    backdrop:refresh()

    eq(1, #drawn)
    eq({ row = 3, col = 3, cols = 22, rows = 10, z = -1500000000 }, drawn[1].place)
    eq({ 22 * 8, 10 * 16 }, { drawn[1].width, drawn[1].height })
    eq(22 * 8 * 10 * 16 * 4, #drawn[1].bytes)
  end)

  it('draws nothing on a second refresh when nothing changed', function()
    local backdrop = backdrop_for(float({}))

    backdrop:refresh():refresh()

    eq(1, #drawn)
  end)

  it('repaints at the new place when the window moves, replacing the image it had', function()
    local win = float({})
    local backdrop = backdrop_for(win)

    backdrop:refresh()
    vim.api.nvim_win_set_config(win, { relative = 'editor', row = 4, col = 6, width = 20, height = 8 })
    backdrop:refresh()
    vim.api.nvim_win_set_config(win, { relative = 'editor', row = 5, col = 7, width = 20, height = 8 })
    backdrop:refresh()

    eq(3, #drawn)
    eq({ row = 5, col = 7, cols = 20, rows = 8, z = -1500000000 }, drawn[2].place)
    eq({ nil, drawn[1].id, drawn[2].id }, { drawn[1].replaced, drawn[2].replaced, drawn[3].replaced })
    eq({ drawn[1].id, drawn[2].id, drawn[1].id }, { drawn[1].id, drawn[2].id, drawn[3].id })
  end)

  it('repaints when its content is invalidated', function()
    local backdrop = backdrop_for(float({}))

    backdrop:refresh():refresh()
    eq(1, #drawn)

    backdrop:invalidate():refresh()
    eq(2, #drawn)
  end)

  it('repaints when its key changes, and not when the key stays the same', function()
    local state = 'a'
    local backdrop = Backdrop({
      window = Window(float({})),
      draw = fill,
      key = function()
        return state
      end,
    })

    backdrops[#backdrops + 1] = backdrop

    backdrop:refresh():refresh()
    eq(1, #drawn)

    state = 'b'
    backdrop:refresh()
    eq(2, #drawn)
  end)

  it('erases the pixels under a higher float, and repaints them whole when it closes', function()
    local backdrop = backdrop_for(float({}))

    backdrop:refresh()

    local above = float({ row = 2, col = 12, width = 10, height = 8, zindex = 60 })

    backdrop:refresh()

    eq({ 0, 255 }, { alpha(drawn[2].bytes, 160, 84, 4), alpha(drawn[2].bytes, 160, 16, 4) })

    vim.api.nvim_win_close(above, true)
    backdrop:refresh()

    eq(3, #drawn)
    eq(255, alpha(drawn[3].bytes, 160, 84, 4))
  end)

  it('hides without drawing when a higher float covers it entirely', function()
    local backdrop = backdrop_for(float({}))

    backdrop:refresh()
    float({ zindex = 60 })
    backdrop:refresh()

    eq({ drawn[1].id }, deleted)
    eq(1, #drawn)
  end)

  it('deletes its image and unregisters itself on destroy', function()
    local backdrop = backdrop_for(float({}))
    local before = Backdrop.count()

    backdrop:refresh()
    backdrop:destroy()

    eq({ drawn[1].id }, deleted)
    eq(before - 1, Backdrop.count())
  end)

  it('destroys a backdrop whose window is closed on refresh_all', function()
    local win = float({})
    backdrop_for(win)

    local before = Backdrop.count()

    vim.api.nvim_win_close(win, true)
    Backdrop.refresh_all()

    eq(before - 1, Backdrop.count())
  end)

  it('hides a backdrop whose window is on another tabpage on refresh_all', function()
    local backdrop = backdrop_for(float({}))

    backdrop:refresh()
    vim.cmd('tabnew')
    Backdrop.refresh_all()
    vim.cmd('tabclose')

    eq({ drawn[1].id }, deleted)
  end)
end)

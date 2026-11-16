local Tile = require('ui.pixel.Tile')
local Toast = require('harness.ui.Toast')
local graphics = require('core.graphics')
local ticker = require('ui.pixel.ticker')
local theme_settings = require('harness.settings.theme')

local eq = assert.are.same

local function reduce(on)
  theme_settings:assign({ motion = vim.tbl_extend('force', theme_settings:get('motion'), { reduced = on }) })
end

local function rings(window)
  local bufnr = window:get_buffer().bufnr
  local found = {}

  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
    if mark[4].virt_text then found[#found + 1] = mark end
  end

  return found
end

describe('harness.ui.Toast:', function()
  after_each(function()
    Toast.dismiss()
  end)

  it('floats a one-line window at the top right, faded out until it eases in', function()
    local window = Toast.show('session finished')
    local config = window:get_config()

    eq('editor', config.relative)
    eq(1, config.height)
    eq(false, config.focusable)
    eq(Toast.BLEND_HIDDEN, window:get_option('winblend'))
    assert.is_truthy(
      vim.api.nvim_buf_get_lines(window:get_buffer().bufnr, 0, -1, false)[1]:find('session finished', 1, true)
    )
    eq(true, Toast.visible())
  end)

  it('eases in on its own, and shows only the latest message', function()
    local first = Toast.show('one')
    local second = Toast.show('two')

    eq(false, first:is_valid())

    vim.wait(400, function()
      return second:get_option('winblend') == Toast.BLEND_SHOWN
    end)

    eq(Toast.BLEND_SHOWN, second:get_option('winblend'))
  end)

  it('closes its window and buffer when dismissed', function()
    local window = Toast.show('bye')
    local bufnr = window:get_buffer().bufnr

    Toast.dismiss()

    eq(false, window:is_valid())
    eq(false, vim.api.nvim_buf_is_valid(bufnr))
    eq(false, Toast.visible())
  end)

  it('fades out and closes itself after its hold', function()
    local settings = require('harness.settings')
    local saved = settings.transcript:get('toast')

    settings.transcript:assign({ toast = { in_ms = 10, hold_ms = 20, out_ms = 20 } })

    local window = Toast.show('quick')

    vim.wait(1000, function()
      return not window:is_valid()
    end)
    settings.transcript:assign({ toast = saved })

    eq(false, window:is_valid())
    eq(false, Toast.visible())
  end)

  describe('with pixels for a countdown ring', function()
    local original, deleted

    before_each(function()
      deleted = 0
      original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
      Tile.available = function()
        return true
      end
      graphics.upload = function() end
      graphics.delete = function()
        deleted = deleted + 1
      end
    end)

    after_each(function()
      Toast.dismiss()
      reduce(false)
      ticker.stop()
      Tile.drain()
      Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
    end)

    it('widens the toast by the ring and places the ring as one text mark at its right end', function()
      Tile.available = function()
        return false
      end

      local plain = Toast.show('ring'):get_config().width

      Tile.available = function()
        return true
      end

      local window = Toast.show('ring')
      local line = vim.api.nvim_buf_get_lines(window:get_buffer().bufnr, 0, -1, false)[1]
      local found = rings(window)

      eq(plain + Toast.RING_COLS + 1, window:get_config().width)
      eq(1, #found)
      eq(0, found[1][2])
      eq(#line - Toast.RING_COLS - 1, found[1][3])
    end)

    it('frees its image as soon as it is dismissed', function()
      Toast.show('bye')
      eq(0, deleted)

      Toast.dismiss()
      eq(1, deleted)
    end)

    it('is exactly as before under reduced motion', function()
      Tile.available = function()
        return false
      end

      local plain = Toast.show('calm'):get_config().width

      Tile.available = function()
        return true
      end
      reduce(true)

      local window = Toast.show('calm')

      eq(plain, window:get_config().width)
      eq({}, rings(window))
    end)

    it('is exactly as before where there are no pixels', function()
      Tile.available = function()
        return false
      end

      local window = Toast.show('plain')

      eq({}, rings(window))
    end)
  end)
end)

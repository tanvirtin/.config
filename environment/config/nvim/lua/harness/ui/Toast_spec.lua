local Toast = require('harness.ui.Toast')

local eq = assert.are.same

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
end)

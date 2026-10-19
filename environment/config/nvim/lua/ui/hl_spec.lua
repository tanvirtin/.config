local hl = require('ui.hl')

local eq = assert.are.same

describe('ui.hl:', function()
  it('blends two colours channel by channel', function()
    eq(0x000000, hl.blend(0xffffff, 0x000000, 0))
    eq(0xffffff, hl.blend(0xffffff, 0x000000, 1))
    eq(0x808080, hl.blend(0xffffff, 0x000000, 0.5))
    eq(0x1a0000, hl.blend(0xff0000, 0x000000, 0.1))
  end)

  it('tints the prompt background from the accent and the normal background', function()
    vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = 0x000000 })
    vim.api.nvim_set_hl(0, 'UiAccent', { fg = 0xff0000 })
    hl.define()

    eq(0x1a0000, vim.api.nvim_get_hl(0, { name = 'UiPrompt' }).bg)
  end)
end)

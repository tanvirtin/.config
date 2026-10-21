local hl = require('ui.hl')

local eq = assert.are.same

describe('ui.hl:', function()
  it('blends two colours channel by channel', function()
    eq(0x000000, hl.blend(0xffffff, 0x000000, 0))
    eq(0xffffff, hl.blend(0xffffff, 0x000000, 1))
    eq(0x808080, hl.blend(0xffffff, 0x000000, 0.5))
    eq(0x1a0000, hl.blend(0xff0000, 0x000000, 0.1))
  end)

  it('draws the prompt marker in the accent and the prompt text bold', function()
    vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = 0x000000 })
    vim.api.nvim_set_hl(0, 'UiAccent', { fg = 0xff0000 })
    hl.define()

    eq({ 0xff0000, true }, {
      vim.api.nvim_get_hl(0, { name = 'UiPromptBar' }).fg,
      vim.api.nvim_get_hl(0, { name = 'UiPromptText' }).bold,
    })
  end)

  describe('surfaces', function()
    local saved

    before_each(function()
      saved = {
        Normal = vim.api.nvim_get_hl(0, { name = 'Normal' }),
        Comment = vim.api.nvim_get_hl(0, { name = 'Comment' }),
        Added = vim.api.nvim_get_hl(0, { name = 'Added' }),
      }
      vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = 0x000000 })
      vim.api.nvim_set_hl(0, 'Comment', { fg = 0x808080 })
      vim.api.nvim_set_hl(0, 'Added', { fg = 0x00ff00 })
    end)

    after_each(function()
      for group, spec in pairs(saved) do
        vim.api.nvim_set_hl(0, group, spec)
      end

      hl.clear_overrides()
    end)

    it('blends code, output and diff backgrounds from the scheme\'s own colours', function()
      hl.define()

      eq(hl.blend(0xffffff, 0x000000, 0.06), vim.api.nvim_get_hl(0, { name = 'UiMarkdownCode' }).bg)
      eq(hl.blend(0x808080, 0x000000, 0.08), vim.api.nvim_get_hl(0, { name = 'UiToolOutput' }).bg)
      eq(hl.blend(0x00ff00, 0x000000, 0.16), vim.api.nvim_get_hl(0, { name = 'UiDiffAdd' }).bg)
    end)

    it('falls back to links when the scheme sets no background', function()
      vim.api.nvim_set_hl(0, 'Normal', {})
      hl.define()

      eq('ColorColumn', vim.api.nvim_get_hl(0, { name = 'UiMarkdownCode' }).link)
      eq('DiffAdd', vim.api.nvim_get_hl(0, { name = 'UiDiffAdd' }).link)
    end)

    it('lets overrides win, and keeps them across colour scheme changes', function()
      hl.override({ UiToolOutput = { bg = 0x123456 } })
      hl.define()

      eq(0x123456, vim.api.nvim_get_hl(0, { name = 'UiToolOutput' }).bg)

      hl.clear_overrides()

      eq(hl.blend(0x808080, 0x000000, 0.08), vim.api.nvim_get_hl(0, { name = 'UiToolOutput' }).bg)
    end)
  end)
end)

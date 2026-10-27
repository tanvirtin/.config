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

    it('shares one default block surface with the terminal, and leaves command output on Normal', function()
      hl.define()

      eq(vim.api.nvim_get_hl(0, { name = 'UiTerminal' }).bg, vim.api.nvim_get_hl(0, { name = 'UiMarkdownCode' }).bg)
      eq(0x000000, vim.api.nvim_get_hl(0, { name = 'UiToolOutput' }).bg)
    end)

    it('keeps the default surface a shade below the background, close to it', function()
      vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = 0x404040 })
      hl.define()

      local normal = 0x404040
      local code = vim.api.nvim_get_hl(0, { name = 'UiMarkdownCode' }).bg
      local terminal = vim.api.nvim_get_hl(0, { name = 'UiTerminal' })

      local function channel(value, shift)
        return math.floor(value / 2 ^ shift) % 256
      end

      local function within(from, to, delta)
        for _, shift in ipairs({ 16, 8, 0 }) do
          if math.abs(channel(from, shift) - channel(to, shift)) > delta then return false end
        end

        return true
      end

      assert.is_true(code < normal)
      eq(code, terminal.bg)
      assert.is_true(within(code, normal, 12))
      eq(nil, terminal.fg)
    end)

    it('keeps diff line numbers foreground-only, so the line fill shows through', function()
      local saved = vim.api.nvim_get_hl(0, { name = 'GitLineNr' })

      vim.api.nvim_set_hl(0, 'GitLineNr', { fg = 0x888888, bg = 0x111111 })
      hl.define()

      local number = vim.api.nvim_get_hl(0, { name = 'UiDiffNumber' })

      vim.api.nvim_set_hl(0, 'GitLineNr', saved)

      eq(0x888888, number.fg)
      eq(nil, number.bg)
    end)

    it('draws the artifact border as a dim line, not the scheme foreground', function()
      vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = 0x000000 })
      hl.define()

      local border = vim.api.nvim_get_hl(0, { name = 'UiArtifactBorder' })

      eq(hl.blend(0xffffff, 0x000000, 0.16), border.fg)
      eq(nil, border.bg)
    end)

    it('falls back to links when the scheme sets no background', function()
      vim.api.nvim_set_hl(0, 'Normal', {})
      hl.define()

      eq('ColorColumn', vim.api.nvim_get_hl(0, { name = 'UiMarkdownCode' }).link)
      eq('ColorColumn', vim.api.nvim_get_hl(0, { name = 'UiTerminal' }).link)
    end)

    it('lets overrides win, and keeps them across colour scheme changes', function()
      hl.override({ UiToolOutput = { bg = 0x123456 } })
      hl.define()

      eq(0x123456, vim.api.nvim_get_hl(0, { name = 'UiToolOutput' }).bg)

      hl.clear_overrides()

      eq(0x000000, vim.api.nvim_get_hl(0, { name = 'UiToolOutput' }).bg)
    end)

    it('maps a role to a theme group, or computes its spec', function()
      hl.override({
        UiMuted = 'Title',
        UiAccent = function()
          return { fg = 0x123456 }
        end,
      })
      hl.define()

      eq('Title', vim.api.nvim_get_hl(0, { name = 'UiMuted' }).link)
      eq(0x123456, vim.api.nvim_get_hl(0, { name = 'UiAccent' }).fg)
    end)
  end)
end)

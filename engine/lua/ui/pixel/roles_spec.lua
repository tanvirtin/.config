local roles = require('ui.pixel.roles')

local eq = assert.are.same

describe('ui.pixel.roles:', function()
  after_each(function()
    vim.api.nvim_set_hl(0, 'UiAccent', {})
    vim.api.nvim_set_hl(0, 'UiSurface', {})
  end)

  it('passes a number through as its colour', function()
    eq(0x102030, roles.resolve(0x102030))
  end)

  it('parses a hex string into its colour', function()
    eq(0xff8000, roles.resolve('#ff8000'))
  end)

  it('resolves a role name through its highlight group', function()
    vim.api.nvim_set_hl(0, 'UiAccent', { fg = 0x112233 })

    eq(0x112233, roles.resolve('accent'))
  end)

  it('uses the background when the group has no foreground', function()
    vim.api.nvim_set_hl(0, 'UiSurface', { bg = 0x445566 })

    eq(0x445566, roles.resolve('surface'))
  end)

  it('falls back to white for an unknown name or nil', function()
    eq(roles.FALLBACK, roles.resolve('no-such-role'))
    eq(roles.FALLBACK, roles.resolve(nil))
  end)

  it('turns a colour name into its three channels', function()
    vim.api.nvim_set_hl(0, 'UiAccent', { fg = 0x102030 })

    eq({ 0x10, 0x20, 0x30 }, roles.rgb('accent'))
    eq({ 0xff, 0x80, 0x00 }, roles.rgb('#ff8000'))
  end)

  it('returns a table of channels unchanged from rgb', function()
    local channels = { 1, 2, 3 }

    assert.are.equal(channels, roles.rgb(channels))
  end)

  it('converts a table of channels to a number in resolve', function()
    eq(0x102030, roles.resolve({ 0x10, 0x20, 0x30 }))
  end)

  it('fills with the editor background when a group has no background of its own', function()
    local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })

    vim.api.nvim_set_hl(0, 'RolesSpecNoBg', { fg = 0x123456 })
    vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = 0x101010 })

    local background = roles.background('RolesSpecNoBg')

    vim.api.nvim_set_hl(0, 'Normal', normal)

    assert.are.same(0x101010, background)
  end)
end)

local Bitmap = require('ui.pixel.Bitmap')
local hl = require('ui.hl')
local surface = require('ui.pixel.surface')

local eq = assert.are.same

local WIDTH, HEIGHT = 160, 96

local function card(overrides)
  return vim.tbl_extend(
    'force',
    { fill = 'SurfaceSpecFill', border = false, shadow = 0, radius = surface.RADIUS },
    overrides or {}
  )
end

local function paint(spec, focused)
  local bitmap = Bitmap.new(WIDTH, HEIGHT)

  surface.draw(bitmap, { width = WIDTH, height = HEIGHT }, spec, focused)

  return bitmap
end

describe('ui.pixel.surface:', function()
  before_each(function()
    vim.api.nvim_set_hl(0, 'SurfaceSpecFill', { bg = 0x203040 })
    vim.api.nvim_set_hl(0, 'SurfaceSpecBorder', { fg = 0xff0000 })
    vim.api.nvim_set_hl(0, 'SurfaceSpecFocus', { fg = 0x00ff00 })
    vim.api.nvim_set_hl(0, 'SurfaceSpecOther', { bg = 0x804020 })
  end)

  after_each(function()
    vim.api.nvim_set_hl(0, 'SurfaceSpecFill', {})
    vim.api.nvim_set_hl(0, 'SurfaceSpecBorder', {})
    vim.api.nvim_set_hl(0, 'SurfaceSpecFocus', {})
    vim.api.nvim_set_hl(0, 'SurfaceSpecOther', {})
  end)

  it('resolves true to the surface elevation with its radius', function()
    local resolved = surface.resolve(true)

    eq({ elevation = 'surface', fill = 'UiSurface', border = 'UiBorder', shadow = 0, radius = 10 }, resolved)
  end)

  it('resolves the raised and modal elevations to their fill, border and shadow', function()
    eq({ 'UiSurfaceRaised', 'UiBorder', 0.22 }, {
      surface.resolve({ elevation = 'raised' }).fill,
      surface.resolve({ elevation = 'raised' }).border,
      surface.resolve({ elevation = 'raised' }).shadow,
    })
    eq({ 'UiSurfaceRaised', 'UiAccent', 0.32 }, {
      surface.resolve({ elevation = 'modal' }).fill,
      surface.resolve({ elevation = 'modal' }).border,
      surface.resolve({ elevation = 'modal' }).shadow,
    })
  end)

  it('takes a fill and a focus role from the spec over the elevation fill', function()
    local resolved = surface.resolve({ elevation = 'raised', fill = 'SurfaceSpecOther', focus = 'UiAccent' })

    eq({ 'SurfaceSpecOther', 'UiAccent' }, { resolved.fill, resolved.focus })
    eq(nil, surface.resolve({ elevation = 'raised' }).focus)
  end)

  it('takes a border role, a radius, or no border from the spec', function()
    eq(
      { 'UiAccent', 6 },
      { surface.resolve({ border = 'UiAccent', radius = 6 }).border, surface.resolve({ radius = 6 }).radius }
    )
    eq(false, surface.resolve({ border = false }).border)
  end)

  it('errors on an unknown elevation and names the known ones', function()
    local ok, err = pcall(surface.resolve, { elevation = 'loud' })

    eq(false, ok)
    assert.is_truthy(err:find('unknown elevation loud (surface, raised, modal)', 1, true))
  end)

  it('paints the card in its fill colour, opaque, inside the window', function()
    local bitmap = paint(card())

    eq({ 0x20, 0x30, 0x40, 255 }, { bitmap:pixel(80, 48) })
  end)

  it('leaves the window corner transparent', function()
    local bitmap = paint(card({ shadow = 0.22 }))

    eq(0, select(4, bitmap:pixel(0, 0)))
  end)

  it('paints the border line in a colour other than the fill', function()
    local bitmap = paint(card({ border = 'SurfaceSpecBorder' }))
    local r, _, _, alpha = bitmap:pixel(80, 2)

    assert.is_true(r > 0x20)
    eq(255, alpha)
  end)

  it('paints the border in the focus colour only while the window is focused', function()
    local spec = card({ border = 'SurfaceSpecBorder', focus = 'SurfaceSpecFocus' })
    local _, green_unfocused = paint(spec, false):pixel(80, 2)
    local _, green_focused = paint(spec, true):pixel(80, 2)

    assert.is_true(green_focused > green_unfocused + 100)
  end)

  it('keeps the spec border while focused when no focus role is set', function()
    local spec = card({ border = 'SurfaceSpecBorder' })

    eq({ paint(spec, false):pixel(80, 2) }, { paint(spec, true):pixel(80, 2) })
  end)

  it('casts a soft shadow just below the card only when the shadow is above zero', function()
    eq(0, select(4, paint(card({ shadow = 0 })):pixel(80, 94)))
    assert.is_true(select(4, paint(card({ shadow = 0.22 })):pixel(80, 94)) > 0)
  end)

  it('remaps the normal and border groups of a window and keeps the others in order', function()
    eq(
      'Normal:UiBackdropNormal,FloatBorder:UiBackdropNormal,CursorLine:UiSelected',
      surface.winhl('Normal:UiNormal,FloatBorder:UiMuted,CursorLine:UiSelected')
    )
  end)

  it('remaps the winbar groups only when the window already lists them', function()
    eq(
      'Normal:UiBackdropNormal,WinBar:UiBackdropNormal,WinBarNC:UiBackdropNormal',
      surface.winhl('Normal:UiComposer,WinBar:WinBar,WinBarNC:WinBarNC')
    )
    eq('Normal:UiBackdropNormal,CursorLine:UiSelected', surface.winhl('Normal:UiComposer,CursorLine:UiSelected'))
  end)

  it('starts a winhl with the normal group when there is none', function()
    eq('Normal:UiBackdropNormal', surface.winhl(nil))
    eq('Normal:UiBackdropNormal', surface.winhl(''))
  end)

  it('gives the window a blank one cell frame', function()
    eq({ ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' }, surface.window_border(true))
  end)

  it('draws the surfaced text with no background of its own', function()
    local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })

    vim.api.nvim_set_hl(0, 'Normal', { fg = 0xffffff, bg = 0x000000 })
    hl.define()

    local group = vim.api.nvim_get_hl(0, { name = surface.GROUP })

    vim.api.nvim_set_hl(0, 'Normal', normal)
    hl.define()

    eq({ 0xffffff, nil }, { group.fg, group.bg })
  end)
end)

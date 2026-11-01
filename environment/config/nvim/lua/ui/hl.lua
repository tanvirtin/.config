local motion = require('ui.motion')

local hl = {}

hl.PULSE_STEPS = 12
hl.FLASH_STEPS = 8
hl.FLASH_PEAK = 0.24

hl.GROUPS = {
  UiNormal = 'NormalFloat',
  UiBorder = 'FloatBorder',
  UiTitle = 'Title',
  UiSelected = 'CursorLine',
  UiMuted = 'Comment',
  UiAccent = 'Special',
  UiWorking = 'Special',
  UiWorking1 = 'Special',
  UiWorking2 = 'Directory',
  UiWorking3 = 'DiagnosticInfo',
  UiWorking4 = 'Constant',
  UiWorking5 = 'Function',
  UiWorking6 = 'Keyword',
  UiPath = 'Directory',
  UiLineNr = 'LineNr',
  UiAdded = 'Added',
  UiRemoved = 'Removed',
  UiError = 'DiagnosticError',
  UiWarn = 'DiagnosticWarn',
  UiInfo = 'DiagnosticInfo',
  UiHint = 'DiagnosticHint',
  UiMarkdownHeading1 = '@markup.heading.1.markdown',
  UiMarkdownHeading2 = '@markup.heading.2.markdown',
  UiMarkdownHeading3 = '@markup.heading.3.markdown',
  UiMarkdownHeading4 = '@markup.heading.4.markdown',
  UiMarkdownHeading5 = '@markup.heading.5.markdown',
  UiMarkdownHeading6 = '@markup.heading.6.markdown',
  UiMarkdownBullet = 'Special',
  UiMarkdownQuote = 'Comment',
  UiMarkdownRule = 'WinSeparator',
  UiMarkdownLink = 'Underlined',
  UiMarkdownChecked = 'DiagnosticOk',
  UiMarkdownUnchecked = 'Comment',
  UiMarkdownTableHeader = '@markup.heading.markdown',
  UiMarkdownTableCell = 'Normal',
  UiTurnSeparator = 'WinSeparator',
  UiExternalChange = 'DiffChange',
  UiToolName = 'Function',
  UiToolPending = 'DiagnosticInfo',
  UiToolDone = 'DiagnosticOk',
  UiToolFailed = 'DiagnosticError',
}

local function color(group, key)
  local ok, spec = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })

  return ok and spec[key] or nil
end

function hl.blend(fg, bg, alpha)
  local function channel(value, shift)
    return math.floor(value / 2 ^ shift) % 256
  end

  local out = 0

  for _, shift in ipairs({ 16, 8, 0 }) do
    local mixed = math.floor(channel(fg, shift) * alpha + channel(bg, shift) * (1 - alpha) + 0.5)
    out = out + mixed * 2 ^ shift
  end

  return out
end

local function shade(strength, fallback)
  return function()
    local background = color('Normal', 'bg')

    if not background then return { link = fallback } end

    return { bg = hl.blend(0x000000, background, strength) }
  end
end

hl.ANSI = {
  [0] = 'Comment',
  'DiagnosticError',
  'DiagnosticOk',
  'DiagnosticWarn',
  'DiagnosticInfo',
  'Constant',
  'DiagnosticHint',
  'Normal',
  'Comment',
  'DiagnosticError',
  'DiagnosticOk',
  'DiagnosticWarn',
  'DiagnosticInfo',
  'Constant',
  'DiagnosticHint',
  'Normal',
}

local function ansi(n)
  return function()
    local terminal = vim.g['terminal_color_' .. n]

    if type(terminal) == 'string' and terminal ~= '' then return { fg = terminal } end

    return { fg = color(hl.ANSI[n], 'fg') or color('Normal', 'fg') }
  end
end

local SURFACE = 0.12

local function number(group, fallback)
  return function()
    return { fg = color(group, 'fg') or color(fallback, 'fg') }
  end
end

local function surface(strength, tint, fallback)
  return function()
    local background, foreground = color('Normal', 'bg'), color(tint, 'fg') or color('Normal', 'fg')

    if not background or not foreground then return { link = fallback } end

    return { bg = hl.blend(foreground, background, strength) }
  end
end

local function rail(tint, fallback)
  return function()
    local foreground = color(tint, 'fg')

    if not foreground then return { link = fallback } end

    return { fg = foreground }
  end
end

hl.SURFACE_BASE = 0.05
hl.SURFACE_RAISED = 0.09
hl.SURFACE_TINT = 0.1

hl.COMPUTED = {
  UiSurface = surface(hl.SURFACE_BASE, 'Normal', 'ColorColumn'),
  UiSurfaceRaised = surface(hl.SURFACE_RAISED, 'Normal', 'CursorLine'),
  UiSurfaceWarn = surface(hl.SURFACE_TINT, 'UiWarn', 'ColorColumn'),
  UiSurfaceError = surface(hl.SURFACE_TINT, 'UiError', 'ColorColumn'),
  UiSurfaceAccent = surface(hl.SURFACE_TINT, 'UiAccent', 'ColorColumn'),
  UiComposer = function()
    local foreground, background = color('Normal', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'Normal' } end

    return { fg = foreground, bg = hl.blend(foreground, background, hl.SURFACE_BASE) }
  end,
  UiRailAccent = rail('UiAccent', 'Special'),
  UiRailWarn = rail('UiWarn', 'DiagnosticWarn'),
  UiRailError = rail('UiError', 'DiagnosticError'),
  UiRailInfo = rail('UiInfo', 'DiagnosticInfo'),
  UiRailMuted = rail('UiMuted', 'Comment'),
  UiMarkdownCode = shade(SURFACE, 'ColorColumn'),
  UiToolOutput = function()
    return { bg = color('Normal', 'bg') }
  end,
  UiTerminal = shade(SURFACE, 'ColorColumn'),
  UiArtifactBorder = function()
    local foreground, background = color('Normal', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'WinSeparator' } end

    return { fg = hl.blend(foreground, background, 0.16) }
  end,
  UiDiffNumber = number('GitLineNr', 'LineNr'),
  UiDiffAddNumber = number('GitSignsAdd', 'Added'),
  UiDiffDeleteNumber = number('GitSignsDelete', 'Removed'),
  UiPromptBar = function()
    return { fg = color('UiAccent', 'fg'), bold = true }
  end,
  UiPromptText = function()
    return { fg = color('Normal', 'fg'), bold = true }
  end,
  UiAnsiBold = function()
    return { bold = true }
  end,
}

for i = 1, hl.PULSE_STEPS do
  local alpha = 0.3 + 0.7 * motion.breath(hl.PULSE_STEPS, i)

  hl.COMPUTED['UiPulse' .. i] = function()
    local accent = color('UiWorking', 'fg') or color('UiAccent', 'fg') or color('Special', 'fg')
    local background = color('Normal', 'bg')

    if not accent or not background then return { link = i <= hl.PULSE_STEPS / 2 and 'UiAccent' or 'UiMuted' } end

    return { fg = hl.blend(accent, background, alpha) }
  end
end

for i = 1, hl.PULSE_STEPS do
  local alpha = 0.35 + 0.65 * motion.breath(hl.PULSE_STEPS, i)

  hl.COMPUTED['UiPulseWarn' .. i] = function()
    local warn, background = color('UiWarn', 'fg'), color('Normal', 'bg')

    if not warn or not background then return { link = 'UiWarn' } end

    return { fg = hl.blend(warn, background, alpha) }
  end
end

for _, tone in ipairs({ 'Accent', 'Error' }) do
  for i = 1, hl.FLASH_STEPS do
    hl.COMPUTED['UiFlash' .. tone .. i] = function()
      local tint, foreground, background = color('Ui' .. tone, 'fg'), color('Normal', 'fg'), color('Normal', 'bg')

      if not tint or not foreground or not background then return { link = 'UiSurface' .. tone } end

      local peak = hl.blend(tint, background, hl.FLASH_PEAK)
      local rest = hl.blend(foreground, background, hl.SURFACE_BASE)

      return { bg = hl.blend(peak, rest, 1 - (i - 1) / (hl.FLASH_STEPS - 1)) }
    end
  end
end

for n = 0, 15 do
  hl.COMPUTED['UiAnsi' .. n] = ansi(n)
end

local overrides = {}

function hl.override(groups)
  overrides = vim.tbl_extend('force', overrides, groups or {})
  hl.define()
end

function hl.clear_overrides()
  overrides = {}
  hl.define()
end

local function apply(group, spec)
  if spec == false then
    vim.api.nvim_set_hl(0, group, {})
  elseif type(spec) == 'string' then
    vim.api.nvim_set_hl(0, group, { link = spec })
  elseif type(spec) == 'function' then
    vim.api.nvim_set_hl(0, group, spec())
  elseif type(spec) == 'table' then
    vim.api.nvim_set_hl(0, group, spec)
  end
end

function hl.define()
  for group, link in pairs(hl.GROUPS) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end

  for group, compute in pairs(hl.COMPUTED) do
    vim.api.nvim_set_hl(0, group, compute())
  end

  for group, spec in pairs(overrides) do
    apply(group, spec)
  end
end

hl.define()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('ui.hl', { clear = true }),
  callback = hl.define,
})

return hl

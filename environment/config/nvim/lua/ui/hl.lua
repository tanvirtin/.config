local tone = require('ui.tone')
local highlight = require('core.editor.highlight')
local palette = require('ui.design.color')

local hl = {}

hl.FLASH_STEPS = 8
hl.FADE_STEPS = 6
hl.FADE_FLOOR = palette.MIX.fade
hl.THOUGHT = palette.MIX.thought
hl.THOUGHT_STREAM_FLOOR = palette.MIX.thought_stream
hl.FLASH_PEAK = palette.MIX.flash
hl.RULE = palette.MIX.rule
hl.LEGIBLE = palette.CONTRAST
hl.LIFT_STEP = 0.1
hl.THOUGHT_FADE = palette.THOUGHT_FADE

local role = palette.source

hl.GROUPS = {
  UiNormal = role('surface.background'),
  UiBorder = role('border'),
  UiTitle = role('text.title'),
  UiSelected = role('element.selected'),
  UiMuted = role('text.muted'),
  UiAccent = role('text.accent'),
  UiMatch = role('text.match'),
  UiPath = role('text.path'),
  UiLineNr = role('line_number'),
  UiAdded = role('created'),
  UiRemoved = role('deleted'),
  UiError = role('error'),
  UiWarn = role('warning'),
  UiInfo = role('info'),
  UiHint = role('hint'),
  UiMarkdownHeading1 = '@markup.heading.1.markdown',
  UiMarkdownHeading2 = '@markup.heading.2.markdown',
  UiMarkdownHeading3 = '@markup.heading.3.markdown',
  UiMarkdownHeading4 = '@markup.heading.4.markdown',
  UiMarkdownHeading5 = '@markup.heading.5.markdown',
  UiMarkdownHeading6 = '@markup.heading.6.markdown',
  UiMarkdownBullet = role('text.accent'),
  UiMarkdownQuote = role('text.muted'),
  UiMarkdownLink = role('text.link'),
  UiMarkdownChecked = role('success'),
  UiMarkdownUnchecked = role('text.muted'),
  UiMarkdownTableHeader = '@markup.heading.markdown',
  UiMarkdownTableCell = role('text'),
  UiToolName = role('text.function'),
  UiToolPending = role('info'),
  UiToolDone = role('success'),
  UiToolFailed = role('error'),
}

local function color(group, key)
  local ok, spec = pcall(highlight.get_hl_by_name, group)

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

local function luminance(rgb)
  local total = 0

  for shift, weight in pairs({ [16] = 0.2126, [8] = 0.7152, [0] = 0.0722 }) do
    local value = (math.floor(rgb / 2 ^ shift) % 256) / 255

    total = total + weight * (value <= 0.03928 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4)
  end

  return total
end

function hl.contrast(a, b)
  local x, y = luminance(a), luminance(b)

  if x < y then
    x, y = y, x
  end

  return (x + 0.05) / (y + 0.05)
end

function hl.legible(fg, bg, text)
  local mix = 0

  while mix < 1 and hl.contrast(hl.blend(text, fg, mix), bg) < hl.LEGIBLE do
    mix = math.min(1, mix + hl.LIFT_STEP)
  end

  return hl.blend(text, fg, mix)
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
    local terminal = highlight.terminal_color(n)

    if type(terminal) == 'string' and terminal ~= '' then return { fg = terminal } end

    return { fg = color(hl.ANSI[n], 'fg') or color('Normal', 'fg') }
  end
end

local SURFACE = palette.MIX.code

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

hl.SURFACE_BASE = palette.MIX.surface
hl.SURFACE_RAISED = palette.MIX.elevated
hl.SURFACE_TINT = palette.MIX.tint

hl.COMPUTED = {
  UiSurface = surface(hl.SURFACE_BASE, 'Normal', 'ColorColumn'),
  UiSurfaceRaised = surface(hl.SURFACE_RAISED, 'Normal', 'CursorLine'),
  UiBackdropNormal = function()
    local foreground = color('Normal', 'fg')

    if not foreground then return { link = 'Normal' } end

    return { fg = foreground, bg = 'NONE' }
  end,
  UiComposer = function()
    local foreground, background = color('Normal', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'Normal' } end

    return { fg = foreground, bg = hl.blend(foreground, background, hl.SURFACE_BASE) }
  end,
  UiChip = function()
    local foreground, background = color('UiPath', 'fg') or color('Directory', 'fg'), color('Normal', 'bg')
    local text = color('Normal', 'fg')

    if not foreground or not background or not text then return { link = 'UiPath' } end

    return { fg = foreground, bg = hl.blend(text, background, hl.SURFACE_RAISED) }
  end,
  UiRailMuted = rail('UiMuted', 'Comment'),
  UiThought = function()
    local foreground, background = color('Normal', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'Comment' } end

    return { fg = hl.blend(foreground, background, hl.THOUGHT) }
  end,
  UiMarkdownCode = shade(SURFACE, 'ColorColumn'),
  UiToolOutput = function()
    return { bg = color('Normal', 'bg') }
  end,
  UiTerminal = shade(SURFACE, 'ColorColumn'),
  UiTurnSeparator = function()
    local foreground, background = color('Normal', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'WinSeparator' } end

    return { fg = hl.blend(foreground, background, hl.RULE) }
  end,
  UiMarkdownRule = function()
    return { link = 'UiTurnSeparator' }
  end,
  UiArtifactBorder = function()
    local foreground, background = color('Normal', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'WinSeparator' } end

    return { fg = hl.blend(foreground, background, palette.MIX.border) }
  end,
  UiGuide = function()
    local foreground, background = color('Comment', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'Comment' } end

    return { fg = foreground, bg = hl.blend(foreground, background, palette.MIX.border), bold = true, italic = true }
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
  UiGlint = function()
    local accent = color('UiAccent', 'fg')

    if not accent then return { link = 'UiAccent' } end

    return { fg = accent, bold = true }
  end,
  UiGlintSoft = function()
    local accent, text = color('UiAccent', 'fg'), color('Normal', 'fg')

    if not accent or not text then return { link = 'UiAccent' } end

    return { fg = hl.blend(accent, text, palette.MIX.glint) }
  end,
}

local function along(i, count)
  return (i - 1) / (count - 1)
end

local function ramp(prefix, count, tint, alpha_at, fallback)
  for i = 1, count do
    hl.COMPUTED[prefix .. i] = function()
      local from, background = tint(), color('Normal', 'bg')

      if not from or not background then return { link = fallback(i) } end

      return { fg = hl.blend(from, background, alpha_at(i)) }
    end
  end
end

local function foreground_of(group, ...)
  local rest = { ... }

  return function()
    local found = color(group, 'fg')

    for _, other in ipairs(rest) do
      found = found or color(other, 'fg')
    end

    return found
  end
end

ramp('UiFade', hl.FADE_STEPS, foreground_of('Normal'), function(i)
  return hl.FADE_FLOOR + (1 - hl.FADE_FLOOR) * along(i, hl.FADE_STEPS)
end, function()
  return 'UiMuted'
end)

ramp('UiThoughtStream', hl.FADE_STEPS - 1, foreground_of('Normal'), function(i)
  return hl.THOUGHT_STREAM_FLOOR + (hl.THOUGHT - hl.THOUGHT_STREAM_FLOOR) * along(i, hl.FADE_STEPS - 1)
end, function()
  return 'UiThought'
end)

for step, alpha in ipairs(hl.THOUGHT_FADE) do
  hl.COMPUTED['UiThoughtFade' .. step] = function()
    local foreground, background = color('Normal', 'fg'), color('Normal', 'bg')

    if not foreground or not background then return { link = 'UiThought' } end

    return { fg = hl.blend(hl.blend(foreground, background, hl.THOUGHT), background, alpha) }
  end
end

for _, name in ipairs(tone.ALL) do
  local source = tone.SOURCE[name]

  hl.COMPUTED[tone.surface(name)] = surface(hl.SURFACE_TINT, source, 'ColorColumn')
  hl.COMPUTED[tone.rail(name)] = rail(source, source)

  for i = 1, hl.FLASH_STEPS do
    hl.COMPUTED[tone.flash(name, i)] = function()
      local tint, foreground, background = color(source, 'fg'), color('Normal', 'fg'), color('Normal', 'bg')

      if not tint or not foreground or not background then return { link = tone.surface(name) } end

      local peak = hl.blend(tint, background, hl.FLASH_PEAK)
      local rest = hl.blend(foreground, background, hl.SURFACE_BASE)

      return { bg = hl.blend(peak, rest, 1 - along(i, hl.FLASH_STEPS)) }
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
    highlight.set(group, {})
  elseif type(spec) == 'string' then
    highlight.set(group, { link = spec })
  elseif type(spec) == 'function' then
    highlight.set(group, spec())
  elseif type(spec) == 'table' then
    highlight.set(group, spec)
  end
end

hl.LIFTED = {
  'UiAccent',
  'UiPath',
  'UiAdded',
  'UiRemoved',
  'UiError',
  'UiWarn',
  'UiInfo',
  'UiHint',
  'UiToolName',
  'UiToolPending',
  'UiToolDone',
  'UiToolFailed',
  'UiMarkdownBullet',
  'UiMarkdownLink',
  'UiMarkdownChecked',
}

local lifted = {}

local function lift()
  local text, background = color('Normal', 'fg'), color('Normal', 'bg')

  if not text or not background then return end

  for _, group in ipairs(hl.LIFTED) do
    local ok, spec = pcall(highlight.get_hl_by_name, group)
    local fg = ok and spec.fg

    if fg and hl.contrast(fg, background) < hl.LEGIBLE then
      highlight.set(group, vim.tbl_extend('force', spec, { fg = hl.legible(fg, background, text) }))
      lifted[group] = true
    end
  end
end

function hl.define()
  for group in pairs(lifted) do
    if hl.GROUPS[group] then highlight.set(group, { link = hl.GROUPS[group] }) end
  end

  lifted = {}

  for group, link in pairs(hl.GROUPS) do
    highlight.set(group, { link = link, default = true })
  end

  lift()

  for group, compute in pairs(hl.COMPUTED) do
    highlight.set(group, compute())
  end

  for group, spec in pairs(overrides) do
    apply(group, spec)
  end
end

hl.define()

highlight.on_colorscheme('ui.hl', hl.define)

return hl

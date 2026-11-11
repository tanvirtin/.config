local tone = require('ui.tone')
local highlight = require('core.highlight')
local motion = require('ui.motion')

local hl = {}

hl.PULSE_STEPS = 12
hl.FLASH_STEPS = 8
hl.FADE_STEPS = 6
hl.GLINT = { 1, 0.6, 0.25 }
hl.SPARK = { 1, 0.7, 0.45 }
hl.STRIKE_REST = 0.5
hl.STRIKE_LIGHT = 2
hl.FADE_FLOOR = 0.45
hl.THOUGHT = 0.62
hl.FLASH_PEAK = 0.24
hl.RULE = 0.3
hl.LEGIBLE = 3
hl.LIFT_STEP = 0.1

hl.GROUPS = {
  UiNormal = 'NormalFloat',
  UiBorder = 'FloatBorder',
  UiTitle = 'Title',
  UiSelected = 'CursorLine',
  UiMuted = 'Comment',
  UiAccent = 'Special',
  UiWorking = 'Special',
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
  UiMarkdownLink = 'Underlined',
  UiMarkdownChecked = 'DiagnosticOk',
  UiMarkdownUnchecked = 'Comment',
  UiMarkdownTableHeader = '@markup.heading.markdown',
  UiMarkdownTableCell = 'Normal',
  UiExternalChange = 'DiffChange',
  UiToolName = 'Function',
  UiToolPending = 'DiagnosticInfo',
  UiToolDone = 'DiagnosticOk',
  UiToolFailed = 'DiagnosticError',
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

hl.WORKING = {
  'Special',
  'Directory',
  'DiagnosticInfo',
  'Constant',
  'Function',
  'Keyword',
  'String',
  'Type',
  'Number',
  'Identifier',
  'Statement',
  'PreProc',
  'DiagnosticWarn',
  'DiagnosticOk',
  'DiagnosticHint',
}

hl.WORKING_SLOTS = 6
hl.WORKING_FROM_TEXT = 90
hl.WORKING_APART = 40

local function distance(a, b)
  local total = 0

  for _, shift in ipairs({ 16, 8, 0 }) do
    local delta = math.floor(a / 2 ^ shift) % 256 - math.floor(b / 2 ^ shift) % 256

    total = total + delta * delta
  end

  return math.sqrt(total)
end

local function pick_working()
  local text, picked = color('Normal', 'fg'), {}

  for _, group in ipairs(hl.WORKING) do
    local fg = color(group, 'fg')
    local fits = fg ~= nil and (text == nil or distance(fg, text) >= hl.WORKING_FROM_TEXT)

    for _, other in ipairs(picked) do
      if fits and distance(fg, other) < hl.WORKING_APART then fits = false end
    end

    if fits then picked[#picked + 1] = fg end

    if #picked == hl.WORKING_SLOTS then break end
  end

  return picked
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

local function breathing(floor)
  return function(i)
    return floor + (1 - floor) * motion.breath(hl.PULSE_STEPS, i)
  end
end

ramp('UiPulse', hl.PULSE_STEPS, foreground_of('Normal'), breathing(0.3), function(i)
  return i <= hl.PULSE_STEPS / 2 and 'UiAccent' or 'UiMuted'
end)

ramp('UiFade', hl.FADE_STEPS, foreground_of('Normal'), function(i)
  return hl.FADE_FLOOR + (1 - hl.FADE_FLOOR) * along(i, hl.FADE_STEPS)
end, function()
  return 'UiMuted'
end)

ramp('UiSpark', #hl.SPARK, foreground_of('UiAccent'), function(i)
  return hl.SPARK[i]
end, function()
  return 'UiAccent'
end)

for i = 1, hl.PULSE_STEPS do
  hl.COMPUTED['UiStrike' .. i] = function()
    local accent, foreground, background = color('UiAccent', 'fg'), color('Normal', 'fg'), color('Normal', 'bg')

    if not accent or not foreground or not background then return { link = i <= 3 and 'UiAccent' or 'UiMuted' } end

    local rest = hl.blend(foreground, background, hl.STRIKE_REST)

    return { fg = hl.blend(accent, rest, (1 - along(i, hl.PULSE_STEPS)) ^ 3) }
  end
end

for word = 1, 6 do
  for step, mix in ipairs(hl.GLINT) do
    hl.COMPUTED['UiWorkingGlint' .. word .. '_' .. step] = function()
      local accent, own = color('UiAccent', 'fg'), color('UiWorking' .. word, 'fg')

      if not accent or not own then return { link = 'UiAccent' } end

      return { fg = hl.blend(accent, own, mix), bold = step == 1 }
    end
  end
end

for _, name in ipairs(tone.ALL) do
  local source = tone.SOURCE[name]

  hl.COMPUTED[tone.surface(name)] = surface(hl.SURFACE_TINT, source, 'ColorColumn')
  hl.COMPUTED[tone.rail(name)] = rail(source, source)

  ramp('UiPulse' .. name, hl.PULSE_STEPS, foreground_of(source), breathing(0.35), function()
    return source
  end)

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
  'UiWorking',
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

for slot = 1, hl.WORKING_SLOTS do
  hl.LIFTED[#hl.LIFTED + 1] = 'UiWorking' .. slot
end

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

  local picked = pick_working()

  for slot = 1, hl.WORKING_SLOTS do
    local fg = #picked > 0 and picked[(slot - 1) % #picked + 1] or nil

    highlight.set('UiWorking' .. slot, fg and { fg = fg } or { link = hl.WORKING[slot], default = true })
  end

  if #picked > 0 then highlight.set('UiWorking', { fg = picked[1] }) end

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

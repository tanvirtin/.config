local lazy = require('core.lazy')

local tone = require('ui.tone')
local text = require('core.text')
local catalog = require('ui.pixel.catalog')
local orb = require('harness.transcript.orb')
local pip = require('harness.transcript.pip')
local rule = require('harness.transcript.rule')
local meter = require('harness.transcript.meter')
local forge = require('harness.transcript.forge')
local indicators = require('ui.pixel.indicators')
local settings = require('harness.settings.theme')

local hl = lazy('ui.hl')

local loading_bar

local theme = {}

theme.GUTTER_PRIORITY = 10
theme.SYNTAX_PRIORITY = 200
theme.RULE_WIDTH = 400

local FROM_SETTINGS = {
  TOOL_ICONS = 'tool_icons',
  WAITING_ICON = 'waiting_icon',
  QUEUE_ICON = 'queue_icon',
  IDLE_ICON = 'idle_icon',
  CURRENT_ICON = 'current_icon',
  MODE_FORMAT = 'mode_format',
  PLAN_ICONS = 'plan_icons',
  PROMPT_ICON = 'prompt_icon',
  PATH_ICON = 'path_icon',
  VERB_WIDTH = 'verb_width',
  GUTTER = 'gutter',
  SIGN = 'sign',
  BRANCH = 'branch',
  BRANCH_END = 'branch_end',
  RULE = 'rule',
  ARTIFACT_BORDER = 'artifact_border',
  ARTIFACT_RULE = 'artifact_rule',
  HUNK = 'hunk',
  COLLAPSED_ICON = 'collapsed_icon',
}

setmetatable(theme, {
  __index = function(_, key)
    local name = FROM_SETTINGS[key]

    if name then return settings:get(name) end
  end,
})

function theme.reduced()
  return settings:get('motion').reduced == true
end

function theme.beat()
  return settings:get('motion').pulse_ms * hl.PULSE_STEPS
end

local function slot(now, ms)
  return math.floor((now or 0) % theme.beat() / ms) + 1
end

local function spark_slot(now)
  return slot(now, settings:get('motion').working.spark_ms)
end

function theme.pulse(now, name)
  if theme.reduced() then return tone.pulse(name, 1) end

  return tone.pulse(name, slot(now, settings:get('motion').pulse_ms))
end

local function beats(now, started)
  local beat = theme.beat()

  return math.max(0, math.floor((now or 0) / beat) - math.floor((started or now or 0) / beat))
end

local function blow(now, started)
  local light = beats(now, started) % settings:get('motion').working.word_beats ~= 0

  return light and 1 or 0
end

local function spark(now, started)
  if theme.reduced() then return ' ' end

  return settings:get('motion').working.spark[spark_slot(now) + blow(now, started)] or ' '
end

local function strike(now, started)
  if theme.reduced() then return theme.pulse(now) end

  local pulse = settings:get('motion').pulse_ms

  return 'UiStrike' .. math.min(hl.PULSE_STEPS, slot(now, pulse) + blow(now, started) * hl.STRIKE_LIGHT)
end

local function spark_hl(now, started)
  return 'UiSpark' .. math.min(#hl.SPARK, spark_slot(now) + blow(now, started))
end

function theme.working(now, started)
  local spec = settings:get('motion')
  local pixels = not theme.reduced() and forge.chunks(started, theme.beat(), spec.working.word_beats)

  if pixels then return pixels end

  return {
    { settings:get('motion').working.icon, strike(now, started) },
    { spark(now, started), spark_hl(now, started) },
  }
end

function theme.working_text(now)
  return settings:get('motion').working.icon .. spark(now)
end

function theme.badge(now)
  local frames = settings:get('motion').badge.frames

  if theme.reduced() then return { frames[1] .. ' ', theme.pulse(now) } end

  return { frames[slot(now, theme.beat() / #frames)] .. ' ', theme.pulse(now) }
end

function theme.working_word(now, started)
  local spec = settings:get('motion').working

  if not spec or not spec.words or #spec.words == 0 then return nil end

  local index = math.floor(beats(now, started) / spec.word_beats) % #spec.words + 1

  return spec.words[index], 'UiWorking' .. ((index - 1) % 6 + 1)
end

local function fault_beat(index, length, phases)
  if phases <= 1 then return 0 end

  for beat = 1, phases - 1 do
    if ((index * 37 + length * 11) % 5) * (phases - 1) < 5 * beat then return beat end
  end

  return phases - 1
end

local function struck(age, group, tint)
  local pulse = settings:get('motion').pulse_ms

  if age < pulse then return 'UiWorkingGlint' .. tint .. '_1' end
  if age < 2 * pulse then return 'UiWorkingGlint' .. tint .. '_2' end
  if age < 3 * pulse then return 'UiWorkingGlint' .. tint .. '_3' end

  return group
end

local function ingot(now, phase)
  local step = slot(now, settings:get('motion').pulse_ms)

  if phase == 0 then return 'UiIngot' .. math.ceil(step * (#hl.INGOT - 1) / hl.PULSE_STEPS) end

  return 'UiIngot' .. (step <= 2 and step + 1 or #hl.INGOT)
end

function theme.forged(word, group, now, started)
  local tint = group and group:match('^UiWorking(%d)$')

  if theme.reduced() or not tint then return { { word, group } } end

  local spec = settings:get('motion').working
  local beat = theme.beat()
  local phase = started and beats(now, started) % spec.word_beats or spec.word_beats - 1
  local letters = text.chars(word)
  local raw = ingot(now, phase)
  local chunks = {}

  for index, letter in ipairs(letters) do
    local at = fault_beat(index, #letters, spec.word_beats)
    local glyph, name

    if phase >= at then
      glyph = letter
      name = struck(now % beat + (phase - at) * beat, group, tint)
    elseif phase == at - 1 then
      glyph, name = spec.crack, 'UiIngot2'
    else
      glyph, name = spec.ingot, raw
    end

    local last = chunks[#chunks]

    if last and last[2] == name then
      last[1] = last[1] .. glyph
    else
      chunks[#chunks + 1] = { glyph, name }
    end
  end

  return chunks
end

function theme.spinner(now)
  local frames = settings:get('motion').tool.frames

  if theme.reduced() then return theme.TOOL_ICONS.in_progress end

  local pixels = pip.live()

  if pixels then return pixels[1] end

  return { frames[(slot(now, settings:get('motion').pulse_ms) - 1) % #frames + 1] .. ' ', 'UiAccent' }
end

function theme.orb()
  if theme.reduced() then return nil end

  local pixels = orb.live()

  return pixels and pixels[1]
end

function theme.waiting_icon(now)
  if not theme.reduced() then
    local pixel = indicators.chunk('pulse', 'warn')

    if pixel then return pixel end
  end

  return { theme.WAITING_ICON[1], now and theme.pulse(now, tone.WARN) or theme.WAITING_ICON[2] }
end

function theme.burst(key, finished, now, failed)
  if theme.reduced() then return nil end

  local pixels = pip.finish(key, finished, now, failed)

  return pixels and pixels[1]
end

function theme.sweep(now)
  local width = settings:get('motion').loading.width

  if not theme.reduced() then
    loading_bar = loading_bar or catalog.animation('bar', { cols = width, indeterminate = true })

    if loading_bar.props.cols ~= width then loading_bar:set({ cols = width, indeterminate = true }) end

    local pixels = loading_bar:chunks()

    if pixels then return pixels end
  end

  local at = theme.reduced() and 1 or slot(now, theme.beat() / width)
  local out = {}

  for cell = 1, width do
    out[#out + 1] = cell == at and { '▰', 'UiAccent' } or { '▱', 'UiMuted' }
  end

  return out
end

function theme.rule_width(ctx)
  return ctx and ctx.width or theme.RULE_WIDTH
end

function theme.rule(ctx, glyph, group, style, inset)
  local width = theme.rule_width(ctx) - (inset or 0)

  if ctx and ctx.width then
    local pixels = rule.chunks(width, group, style)

    if pixels then return pixels, true end
  end

  return { { string.rep(glyph, width), group } }, false
end

function theme.diffstat(added, removed)
  local squares = meter.diffstat(added, removed)

  if not squares then return {} end

  return { { ' ' }, squares[1] }
end

function theme.meter(done, total, width, group)
  local value = total > 0 and done / total or 0

  return meter.bar(value, width, group)
end

function theme.duration(ms)
  if not ms or ms < 1000 then return nil end

  local seconds = math.floor(ms / 1000)

  if seconds < 60 then return seconds .. 's' end

  return string.format('%dm %ds', math.floor(seconds / 60), seconds % 60)
end

theme.plural = text.plural

return theme

local lazy = require('core.lazy')

local tone = require('ui.tone')
local text = require('core.text')
local settings = require('harness.settings.theme')

local hl = lazy('ui.hl')

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

function theme.glint(group, now, started)
  local word = group and group:match('^UiWorking(%d)$')

  if theme.reduced() or not word then return group end

  local step = spark_slot(now) + blow(now, started)

  if step > #hl.GLINT or step > #settings:get('motion').working.spark then return group end

  return 'UiWorkingGlint' .. word .. '_' .. step
end

function theme.spinner(now)
  local frames = settings:get('motion').tool.frames

  if theme.reduced() then return theme.TOOL_ICONS.in_progress end

  return { frames[(slot(now, settings:get('motion').pulse_ms) - 1) % #frames + 1] .. ' ', 'UiAccent' }
end

function theme.sweep(now)
  local width = settings:get('motion').loading.width
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

function theme.duration(ms)
  if not ms or ms < 1000 then return nil end

  local seconds = math.floor(ms / 1000)

  if seconds < 60 then return seconds .. 's' end

  return string.format('%dm %ds', math.floor(seconds / 60), seconds % 60)
end

theme.plural = text.plural

return theme

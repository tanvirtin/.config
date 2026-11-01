local lazy = require('core.lazy')

local tone = require('ui.tone')
local text = require('core.text')
local motion = require('ui.motion')
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
  RUNNING_ICON = 'running_icon',
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

function theme.motion(kind, now)
  local spec = settings:get('motion')[kind]

  if not spec or not spec.frames or #spec.frames == 0 then return '' end

  local ms = spec.ms or 180
  local index = math.floor((now or 0) / ms) % #spec.frames + 1

  return spec.frames[index]
end

function theme.working_word(now, started)
  local spec = settings:get('motion').working

  if not spec or not spec.words or #spec.words == 0 then return nil end

  local elapsed = math.max(0, (now or 0) - (started or now or 0))
  local ms = spec.word_ms or 3000
  local index = math.floor(elapsed / ms) % #spec.words + 1

  return spec.words[index], 'UiWorking' .. ((index - 1) % 6 + 1)
end

function theme.word_fade(group, now, started)
  local ms = settings:get('motion').working.fade_ms

  if theme.reduced() or not ms or ms <= 0 or not group then return group end

  local spec = settings:get('motion').working
  local into = math.max(0, (now or 0) - (started or now or 0)) % (spec.word_ms or 3000)

  if into >= ms then return group end

  local word = group:match('^UiWorking(%d)$')

  if not word then return group end

  return 'UiWorkingFade' .. word .. '_' .. motion.steps(hl.WORD_FADE_STEPS, into / ms)
end

function theme.pulse(now, name)
  if theme.reduced() then return tone.pulse(name, 1) end

  local ms = settings:get('motion').pulse_ms or 180
  local index = math.floor((now or 0) / ms) % hl.PULSE_STEPS + 1

  return tone.pulse(name, index)
end

function theme.reduced()
  return settings:get('motion').reduced == true
end

function theme.spinner(now)
  if theme.reduced() then return theme.RUNNING_ICON end

  return { theme.motion('loading', now) .. ' ', theme.RUNNING_ICON[2] }
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

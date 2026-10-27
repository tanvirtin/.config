local text = require('core.text')
local settings = require('harness.settings.theme')

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

function theme.pulse(now)
  local ms = settings:get('motion').pulse_ms or 180
  local index = math.floor((now or 0) / ms) % 4 + 1

  return 'UiPulse' .. index
end

function theme.duration(ms)
  if not ms or ms < 1000 then return nil end

  local seconds = math.floor(ms / 1000)

  if seconds < 60 then return seconds .. 's' end

  return string.format('%dm %ds', math.floor(seconds / 60), seconds % 60)
end

theme.plural = text.plural

return theme

local settings = require('harness.settings.theme')

local theme = {}

theme.GUTTER_PRIORITY = 10
theme.SYNTAX_PRIORITY = 200
theme.RULE_WIDTH = 400

local FROM_SETTINGS = {
  SPINNER = 'spinner',
  TOOL_ICONS = 'tool_icons',
  WAITING_ICON = 'waiting_icon',
  QUEUE_ICON = 'queue_icon',
  PROMPT_ICON = 'prompt_icon',
  PATH_ICON = 'path_icon',
  VERB_WIDTH = 'verb_width',
  GUTTER = 'gutter',
  BRANCH = 'branch',
  BRANCH_END = 'branch_end',
  RULE = 'rule',
  HUNK = 'hunk',
  COLLAPSED_ICON = 'collapsed_icon',
}

setmetatable(theme, {
  __index = function(_, key)
    local name = FROM_SETTINGS[key]

    if name then return settings:get(name) end
  end,
})

function theme.spinner(frame)
  local spinner = settings:get('spinner')

  return spinner[((frame or 1) - 1) % #spinner + 1]
end

function theme.duration(ms)
  if not ms or ms < 1000 then return nil end

  local seconds = math.floor(ms / 1000)

  if seconds < 60 then return seconds .. 's' end

  return string.format('%dm %ds', math.floor(seconds / 60), seconds % 60)
end

function theme.plural(n, word)
  return string.format('%d %s%s', n, word, n == 1 and '' or 's')
end

return theme

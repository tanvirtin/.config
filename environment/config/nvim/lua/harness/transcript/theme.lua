local lazy = require('core.lazy')

local text = require('core.text')
local rule = require('harness.transcript.rule')
local meter = require('harness.transcript.meter')
local indicators = require('ui.pixel.indicators')
local settings = require('harness.settings.theme')
local mascot = require('harness.transcript.mascot')

local hl = lazy('ui.hl')

local theme = {}

theme.GUTTER_PRIORITY = 10
theme.SYNTAX_PRIORITY = 200
theme.RULE_WIDTH = 400
theme.LOADER_GROUPS =
  { busy = 'UiAccent', thinking = 'UiThought', waiting = 'UiWarn', loading = 'UiAccent', idle = 'UiMuted' }

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

function theme.working(now, _, mood, owner)
  local pixels = not theme.reduced() and mascot.chunks(mood, owner)

  if pixels then return pixels end

  local kind = mood == 'wait' and 'waiting' or 'busy'

  return { { indicators.glyph(kind, not theme.reduced() and now or nil), theme.LOADER_GROUPS[kind] } }
end

function theme.waning(owner)
  if theme.reduced() then return false end

  return mascot.waning(owner)
end

function theme.waning_chunks(owner, mood)
  if theme.reduced() then return nil end

  return mascot.idle_chunks(owner, mood)
end

function theme.working_text(now)
  return indicators.glyph('busy', not theme.reduced() and now or nil)
end

function theme.loader(kind, now, role)
  if not theme.reduced() then
    local pixel = indicators.chunk(kind, role)

    if pixel then return pixel end
  end

  return { indicators.glyph(kind, not theme.reduced() and now or nil) .. ' ', theme.LOADER_GROUPS[kind] }
end

function theme.burst(key, finished, now, failed)
  if theme.reduced() then return nil end

  return indicators.finish(key, finished, now, failed)
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

function theme.context_ring(share, group)
  local chunks = meter.ring(share, group)

  return chunks and chunks[1] or nil
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

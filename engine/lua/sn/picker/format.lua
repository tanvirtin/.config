local lazy = require('core.lazy')

local text = lazy('core.text')
local EVENT = require('sn.types.events').KIND

local format = {}

format.PROMPT = '> '
format.MODES = { 'sessions', 'agents' }
format.EVENT = EVENT
format.STATE_ROLE = { waiting = 'warn', running = 'accent', idle = 'muted' }
format.STATE_INDICATOR = { waiting = 'waiting', running = 'busy', idle = 'idle' }
format.SECTION = { live = 'Live', recent = 'Recent' }
format.CORPUS_KINDS = { [EVENT.prompt] = true, [EVENT.message] = true }

local function one_line(text)
  return text and (tostring(text):gsub('[\r\n]+', ' ')) or ''
end

local function shorten(value, width)
  return text.truncate(one_line(value), width)
end

local function home(dir)
  if not dir or dir == '' then return '?' end

  return text.display_path(dir)
end

local function state_of(session)
  if #session:waiting() > 0 then return 'waiting', 'UiWarn' end
  if session:running() then return 'running', 'UiAccent' end

  return 'idle', 'UiMuted'
end

local function ago(ms)
  local seconds = math.floor(ms / 1000)

  if seconds < 5 then return 'just now' end
  if seconds < 60 then return seconds .. 's ago' end
  if seconds < 3600 then return math.floor(seconds / 60) .. 'm ago' end
  if seconds < 86400 then return math.floor(seconds / 3600) .. 'h ago' end

  return math.floor(seconds / 86400) .. 'd ago'
end

local function turns_of(session)
  local total = 0

  for _, event in ipairs(session.history) do
    if event.kind == EVENT.prompt and not event.steered then total = total + 1 end
  end

  return total
end

local function usage_of(session)
  for i = #session.history, 1, -1 do
    if session.history[i].kind == EVENT.usage then return session.history[i] end
  end
end

format.one_line = one_line
format.shorten = shorten
format.home = home
format.state_of = state_of
format.ago = ago
format.turns_of = turns_of
format.usage_of = usage_of

return format

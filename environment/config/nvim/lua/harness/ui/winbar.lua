local EVENT = require('harness.events').KIND
local compact = require('compact')
local follow = require('harness.follow')

local winbar = {}

winbar.HINTS = '%#UiAccent# i %#UiMuted#write to this session   %#UiAccent#<leader>. %#UiMuted#sessions'
winbar.STICKY_WIDTH = 80

local function last_usage(session)
  for i = #session.history, 1, -1 do
    if session.history[i].kind == EVENT.usage then return session.history[i] end
  end
end

local function escape(text)
  return (text:gsub('%%', '%%%%'))
end

function winbar.sticky(prompt)
  local first = (prompt.lines[1] or ''):gsub('^> ?', '')

  return '%#UiPromptBar# ▌ %#UiMuted#' .. escape(compact.line(first, winbar.STICKY_WIDTH))
end

function winbar.transcript(session, prompt)
  local parts = { prompt and winbar.sticky(prompt) or winbar.HINTS, '%=' }

  if session.external and follow.is_following(session) then parts[#parts + 1] = '%#UiWarn#⇄ external  ' end

  if session:running() then
    parts[#parts + 1] = '%#UiAccent#● running'
  elseif session.state == 'closed' then
    parts[#parts + 1] = '%#UiMuted#○ closed'
  else
    parts[#parts + 1] = '%#UiMuted#○ idle'
  end

  local mode = session:mode()
  local model = session:choice('model')

  if mode then parts[#parts + 1] = '%#UiAccent#  󰒓 ' .. escape(mode.name or mode.id) end
  if model then parts[#parts + 1] = '%#UiMuted#  ' .. escape(model.name or model.value) end

  local usage = last_usage(session)

  if usage and usage.used and usage.size and usage.size > 0 then
    parts[#parts + 1] = string.format('%%#UiMuted#  ctx %d%%%%', math.floor(usage.used / usage.size * 100 + 0.5))
  end

  if usage and usage.cost then parts[#parts + 1] = string.format('%%#UiMuted#  $%.2f', usage.cost) end

  return table.concat(parts, '') .. ' '
end

return winbar

local EVENT = require('harness.types.events').KIND
local compact = require('compact')
local core_text = require('core.text')
local follow = require('harness.follow')
local keymaps = require('harness.settings.keymaps')
local theme = require('harness.transcript.theme')

local winbar = {}

function winbar.hints()
  local write = keymaps:get('transcript').write

  return string.format(
    '%%#UiAccent# %s %%#UiMuted#write to this session   %%#UiAccent#<leader>. %%#UiMuted#sessions',
    type(write) == 'table' and write[1] or write
  )
end
winbar.STICKY_WIDTH = 80

local function last_usage(session)
  for i = #session.history, 1, -1 do
    if session.history[i].kind == EVENT.usage then return session.history[i] end
  end
end

local function escape(text)
  return (text:gsub('%%', '%%%%'))
end

function winbar.visible_width(text)
  return core_text.width((text:gsub('%%#[^#]*#', ''):gsub('%%%%', '%%'):gsub('%%[<=*]', '')))
end

function winbar.sticky(prompt, width)
  local first = (prompt.lines[1] or ''):gsub('^> ?', '')
  local head = '%#UiPromptBar# ' .. theme.PROMPT_ICON .. ' %#UiMuted#'
  local room = math.max(math.min(width or winbar.STICKY_WIDTH, winbar.STICKY_WIDTH) - winbar.visible_width(head), 8)

  return head .. escape(compact.line(first, room))
end

local function status(session)
  local parts = {}

  if session.external and follow.is_following(session) then parts[#parts + 1] = '%#UiWarn#⇄ external  ' end

  if session:running() then
    parts[#parts + 1] = '%#UiAccent#' .. theme.RUNNING_ICON .. 'running'
  elseif session.state == 'closed' then
    parts[#parts + 1] = '%#UiMuted#' .. theme.IDLE_ICON .. 'closed'
  else
    parts[#parts + 1] = '%#UiMuted#' .. theme.IDLE_ICON .. 'idle'
  end

  local mode = session:mode()
  local model = session:choice('model')

  if mode then parts[#parts + 1] = '%#UiAccent#  ' .. escape(theme.MODE_FORMAT:format(mode.name or mode.id)) end
  if model then parts[#parts + 1] = '%#UiMuted#  ' .. escape(model.name or model.value) end

  local usage = last_usage(session)

  if usage and usage.used and usage.size and usage.size > 0 then
    parts[#parts + 1] = string.format('%%#UiMuted#  ctx %d%%%%', math.floor(usage.used / usage.size * 100 + 0.5))
  end

  if usage and usage.cost then parts[#parts + 1] = string.format('%%#UiMuted#  $%.2f', usage.cost) end

  return table.concat(parts, '') .. ' '
end

function winbar.transcript(session, prompt, width)
  local right = status(session)
  local left = winbar.hints()

  if prompt then left = winbar.sticky(prompt, width and width - winbar.visible_width(right) - 2) end

  return left .. '%<%=' .. right
end

return winbar

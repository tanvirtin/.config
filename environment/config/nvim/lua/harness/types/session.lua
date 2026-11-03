local dataclass = require('core.dataclass')

local session = {}

session.Opened = dataclass.define('OpenedSession', {
  id = { type = 'string' },
  options = {
    type = 'table',
    default = function()
      return {}
    end,
  },
})

session.Stored = dataclass.define('StoredSession', {
  id = { type = 'string', required = true },
  title = { type = 'string' },
  updated_at = { type = 'string' },
})

session.TITLE_LONG = 60

function session.title(text)
  if type(text) ~= 'string' then return nil end

  text = vim.trim((text:gsub('%s+', ' ')))

  local starts = {}

  for at in text:gmatch('[%.!?]%s*()[%u`"]') do
    if at <= #text then starts[#starts + 1] = at end
  end

  if #starts >= 2 or (#starts == 1 and #text > session.TITLE_LONG) then text = text:sub(starts[#starts]) end

  text = text:gsub('%.$', '')

  return text ~= '' and text or nil
end

return session

local settings = {}

settings.NAMES = { 'transcript', 'composer', 'follow', 'sessions', 'skills', 'keymaps', 'theme' }

for _, name in ipairs(settings.NAMES) do
  settings[name] = require('harness.settings.' .. name)
end

function settings.assign(opts)
  local rest = {}

  for key, value in pairs(opts or {}) do
    if settings[key] and type(value) == 'table' then
      settings[key]:assign(value)
    else
      rest[key] = value
    end
  end

  return rest
end

return settings

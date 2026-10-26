local composer_api = {}

local impl

function composer_api.install(value)
  impl = value

  return composer_api
end

local function call(name, ...)
  if not impl then return nil end

  local fn = impl[name]

  if type(fn) ~= 'function' then return nil end

  return fn(...)
end

function composer_api.is_open(...)
  return call('is_open', ...) == true
end

function composer_api.open(...)
  return call('open', ...)
end

function composer_api.interrupt(...)
  return call('interrupt', ...)
end

function composer_api.target(...)
  return call('target', ...)
end

return composer_api

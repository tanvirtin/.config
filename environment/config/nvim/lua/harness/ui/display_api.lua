local display_api = {}

local impl

function display_api.install(value)
  impl = value

  return display_api
end

local function call(name, ...)
  if not impl then return nil end

  local fn = impl[name]

  if type(fn) ~= 'function' then return nil end

  return fn(...)
end

function display_api.view(...)
  return call('view', ...)
end

function display_api.views(...)
  return call('views', ...)
end

function display_api.view_of(...)
  return call('view_of', ...)
end

function display_api.showing(...)
  return call('showing', ...)
end

function display_api.buffer_of(...)
  return call('buffer_of', ...)
end

function display_api.last(...)
  return call('last', ...)
end

function display_api.window(...)
  return call('window', ...)
end

function display_api.open(...)
  return call('open', ...)
end

function display_api.forget(...)
  return call('forget', ...)
end

function display_api.reveal(...)
  return call('reveal', ...)
end

return display_api

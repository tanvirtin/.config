local lazy = require('core.lazy')

local Object = lazy('core.Object')

local Timer = Object:extend()

function Timer:constructor()
  return { _handle = nil }
end

function Timer:_ensure()
  if not self._handle or self._handle:is_closing() then self._handle = vim.uv.new_timer() end

  return self._handle
end

function Timer:start(ms, repeat_ms, callback)
  local handle = self:_ensure()

  handle:stop()
  handle:start(ms, repeat_ms or 0, vim.schedule_wrap(callback))

  return self
end

function Timer:after(ms, callback)
  return self:start(ms, 0, callback)
end

function Timer:every(ms, callback)
  return self:start(ms, ms, callback)
end

function Timer:stop()
  if self._handle and not self._handle:is_closing() then self._handle:stop() end

  return self
end

function Timer:is_active()
  return self._handle ~= nil and not self._handle:is_closing() and self._handle:is_active()
end

function Timer:close()
  if self._handle and not self._handle:is_closing() then
    self._handle:stop()
    self._handle:close()
  end

  self._handle = nil

  return self
end

function Timer.now()
  return vim.uv.now()
end

function Timer.defer(ms, callback)
  vim.defer_fn(callback, ms)
end

function Timer.schedule(callback)
  vim.schedule(callback)
end

function Timer.wait(ms, condition, interval)
  return vim.wait(ms, condition, interval)
end

return Timer

local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')

local Admission = Object:extend()

function Admission:constructor(opts)
  return { store = opts.store, limit = opts.limit, _dispose = nil }
end

function Admission:running()
  local count = 0

  self.store.each(function(session)
    if session:running() then count = count + 1 end
  end)

  return count
end

function Admission:allows(session)
  return session:running() or self:running() < self.limit()
end

function Admission:waiting()
  local waiting = {}

  self.store.each(function(session)
    if session:idle() and session.prompts:size() > 0 then waiting[#waiting + 1] = session end
  end)

  table.sort(waiting, function(a, b)
    return a.prompts:since() < b.prompts:since()
  end)

  return waiting
end

function Admission:release()
  for _, session in ipairs(self:waiting()) do
    if self:running() >= self.limit() then return end

    session.prompts:drain()
  end
end

function Admission:register_events()
  local function later()
    Timer.schedule(function()
      self:release()
    end)
  end

  local on = self.store.on
  local names = self.store.EVENT

  local stop = on(names.event, function(_, event)
    if event.kind == 'stop' then later() end
  end)
  local close = on(names.close, later)

  self._dispose = function()
    stop()
    close()
  end

  return self
end

function Admission:cleanup()
  if self._dispose then self._dispose() end

  self._dispose = nil
end

return Admission

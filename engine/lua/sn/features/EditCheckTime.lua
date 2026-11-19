local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')
local events = lazy('sn.types.events')
local permissions = lazy('sn.permissions')
local buffers = lazy('core.editor.buffers')
local session_store = lazy('sn.session.store')

local EditCheckTime = Object:extend()

EditCheckTime.COMPLETED = 'completed'

function EditCheckTime:constructor()
  return { _dispose = nil }
end

function EditCheckTime.applies(event)
  return event.kind == events.KIND.tool_update
    and event.status == EditCheckTime.COMPLETED
    and permissions.tier(event.name) == nil
end

function EditCheckTime:register_events()
  self._dispose = session_store.on(session_store.EVENT.event, function(_, event)
    if EditCheckTime.applies(event) then Timer.defer(0, buffers.checktime) end
  end)

  return self
end

function EditCheckTime:cleanup()
  if self._dispose then self._dispose() end
  self._dispose = nil
end

return EditCheckTime

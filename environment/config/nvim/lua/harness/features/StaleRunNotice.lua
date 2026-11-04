local lazy = require('core.lazy')

local fs = lazy('core.fs')
local Object = lazy('core.Object')
local console = lazy('core.console')
local events = lazy('harness.types.events')
local session_store = lazy('harness.session_store')

local StaleRunNotice = Object:extend()

StaleRunNotice.COMMAND_WIDTH = 60

function StaleRunNotice:constructor()
  return { _dispose = nil }
end

function StaleRunNotice.applies(session, event)
  return event.kind == events.KIND.stop and event.reason ~= 'error' and session:idle()
end

function StaleRunNotice.message(run)
  local names = vim.tbl_map(fs.basename, run.paths)

  return string.format(
    'Harness: `%s` ran while %s %s unsaved, so it saw the old text; :wa saves them',
    run.command:match('^[^\n]*'):sub(1, StaleRunNotice.COMMAND_WIDTH),
    table.concat(names, ', '),
    #names == 1 and 'was' or 'were'
  )
end

function StaleRunNotice:register_events()
  self._dispose = session_store.on(session_store.EVENT.event, function(session, event)
    if not StaleRunNotice.applies(session, event) then return end

    local runs = session.audit:stale_runs()

    if #runs > 0 then console.notify(StaleRunNotice.message(runs[#runs]), 'warn') end
  end)

  return self
end

function StaleRunNotice:cleanup()
  if self._dispose then self._dispose() end
  self._dispose = nil
end

return StaleRunNotice

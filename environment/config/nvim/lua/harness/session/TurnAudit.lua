local lazy = require('core.lazy')

local Object = lazy('core.Object')
local buffers = lazy('core.buffers')
local events = lazy('harness.types.events')
local editor_context = lazy('harness.context')

local TurnAudit = Object:extend()

function TurnAudit.buffer_modified(path)
  local buffer = buffers.find(path)

  return buffer ~= nil and buffer:is_modified()
end

function TurnAudit:constructor(session, modified)
  return { session = session, modified = modified or TurnAudit.buffer_modified }
end

function TurnAudit:unasked_edits()
  local asked, ids = self.session.log:turn_asked(), {}

  for _, tool in ipairs(self.session.log:turn_tools()) do
    if tool.diffs and not asked[tool.id] then ids[#ids + 1] = tool.id end
  end

  return ids
end

function TurnAudit:_stale_paths(edited, order, at)
  local stale = {}

  for _, path in ipairs(order) do
    if edited[path] < at and self.modified(path) then stale[#stale + 1] = path end
  end

  return stale
end

function TurnAudit:stale_runs()
  local log, runs = self.session.log, {}
  local edited, order, seen = {}, {}, {}

  for i = log:turn_start(), #log.events do
    local event = log.events[i]

    if events.TOOL[event.kind] and event.id then
      for _, diff in ipairs(event.diffs or {}) do
        local path = editor_context.absolute(diff.path, self.session.dir)

        if not edited[path] then
          edited[path] = i
          order[#order + 1] = path
        end
      end

      local command = event.input and event.input.command

      if event.category == 'execute' and type(command) == 'string' and not seen[event.id] then
        seen[event.id] = true

        local stale = self:_stale_paths(edited, order, i)

        if #stale > 0 then runs[#runs + 1] = { command = command, paths = stale } end
      end
    end
  end

  return runs
end

return TurnAudit

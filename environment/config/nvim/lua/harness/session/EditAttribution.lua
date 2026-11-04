local lazy = require('core.lazy')

local Timer = lazy('core.Timer')
local Object = lazy('core.Object')
local events = lazy('harness.types.events')
local editor_context = lazy('harness.context')

local EditAttribution = Object:extend()

EditAttribution.PREFIX = 'editor-edits-'

function EditAttribution:constructor(session)
  return { session = session, loose = {}, seq = 0 }
end

function EditAttribution:pending()
  return #self.loose > 0
end

function EditAttribution:_open_tool()
  for _, tool in ipairs(self.session.log:turn_tools()) do
    if not events.TOOL_FINISHED[tool.status] then return tool.id, tool.diffs or {} end
  end
end

function EditAttribution:_same_file(a, b)
  return a and b and editor_context.absolute(a, self.session.dir) == editor_context.absolute(b, self.session.dir)
end

function EditAttribution:_known(diffs, diff)
  for _, known in ipairs(diffs) do
    if self:_same_file(known.path, diff.path) and known.old == diff.old and known.new == diff.new then return true end
  end

  return false
end

function EditAttribution:_attach(id, diffs, incoming)
  local merged = vim.deepcopy(diffs)

  for _, diff in ipairs(incoming) do
    if not self:_known(merged, diff) then merged[#merged + 1] = { path = diff.path, old = diff.old, new = diff.new } end
  end

  if #merged == #diffs then return false end

  self.session:_emit(events.new({ kind = events.KIND.tool_update, id = id, diffs = merged }))

  return true
end

function EditAttribution:record(diff)
  if not self.session:running() then return false end

  local id, diffs = self:_open_tool()

  if not id then
    self.loose[#self.loose + 1] = diff

    return true
  end

  return self:_attach(id, diffs, { diff })
end

function EditAttribution:_own_entry(loose)
  self.seq = self.seq + 1

  local id = EditAttribution.PREFIX .. self.seq

  self.session:_emit(events.new({
    kind = events.KIND.tool_call,
    id = id,
    name = 'editor edits',
    category = 'edit',
    status = events.TOOL_STATUS.completed,
  }))

  return self:_attach(id, {}, loose)
end

function EditAttribution:settle(ended)
  if #self.loose == 0 then return end

  local id, diffs = self:_open_tool()

  if not id and not ended then return end

  local loose = self.loose

  self.loose = {}

  if id then return self:_attach(id, diffs, loose) end

  local last = self.session.log:turn_tools()[1]

  if last then return self:_attach(last.id, last.diffs or {}, loose) end

  return self:_own_entry(loose)
end

function EditAttribution:settle_soon()
  if not self:pending() then return end

  Timer.defer(0, function()
    self:settle(false)
  end)
end

return EditAttribution

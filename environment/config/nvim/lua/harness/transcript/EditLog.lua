local Block = require('harness.transcript.Block')
local EVENT = require('harness.types.events').KIND

local EditLog = {}

local TOOL = { [EVENT.tool_call] = true, [EVENT.tool_update] = true }

function EditLog.edits(history, from, to)
  from, to = from or 1, to or #history

  local order, tools = {}, {}

  for i, event in ipairs(history) do
    if TOOL[event.kind] and event.id then
      local tool = tools[event.id]

      if not tool then
        tool = { id = event.id, index = i }
        tools[event.id] = tool
        order[#order + 1] = tool
      end

      if event.status then tool.status = event.status end
      if event.diffs and #event.diffs > 0 then tool.diffs = event.diffs end
    end
  end

  local out = {}

  for _, tool in ipairs(order) do
    if tool.diffs and tool.status == Block.STATUS.completed and tool.index >= from and tool.index <= to then
      out[#out + 1] = { id = tool.id, index = tool.index, diffs = tool.diffs }
    end
  end

  return out
end

return EditLog

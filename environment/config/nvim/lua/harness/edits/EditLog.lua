local compact = require('compact')
local Object = require('core.Object')
local Edit = require('harness.edits.Edit')
local context = require('harness.context')
local EVENT = require('harness.types.events').KIND
local edit_text = require('harness.edits.edit_text')

local EditLog = Object:extend()

EditLog.PROMPT_WIDTH = 60

EditLog.COMPLETED = 'completed'

EditLog.CHANGED = { add = 'added', remove = 'removed' }

EditLog.TOOL = { [EVENT.tool_call] = true, [EVENT.tool_update] = true }

local function none()
  return {}
end

function EditLog:constructor(file_lines)
  return { file_lines = file_lines or none, entries = {}, primed = nil }
end

function EditLog.tools(history, from, to)
  from, to = from or 1, to or #history

  local order, tools = {}, {}

  for i, event in ipairs(history) do
    if EditLog.TOOL[event.kind] and event.id then
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
    if tool.diffs and tool.status == EditLog.COMPLETED and tool.index >= from and tool.index <= to then
      out[#out + 1] = { id = tool.id, index = tool.index, diffs = tool.diffs }
    end
  end

  return out
end

function EditLog:get(diff, key, final, failed)
  local entry = self.entries[key]

  if entry and entry.final then return entry.edit end

  local file = self.file_lines(diff.path) or {}
  local fingerprint = table.concat(file, '\n')

  if
    entry
    and entry.fingerprint == fingerprint
    and entry.failed == failed
    and entry.old == diff.old
    and entry.new == diff.new
  then
    entry.final = final
    return entry.edit
  end

  local edit = Edit(diff, file, { failed = failed })

  self.entries[key] = {
    edit = edit,
    final = final,
    failed = failed,
    fingerprint = fingerprint,
    old = diff.old,
    new = diff.new,
  }

  return edit
end

function EditLog:reset()
  self.entries = {}
  self.primed = nil

  return self
end

function EditLog:prime(history)
  if self.primed == #history then return self end

  self.primed = #history

  local files = {}
  local tools = EditLog.tools(history)

  for t = #tools, 1, -1 do
    local tool = tools[t]

    for index = #tool.diffs, 1, -1 do
      local diff = tool.diffs[index]
      local path = diff.path

      if path then
        local key = tool.id .. ':' .. index
        local entry = self.entries[key]

        if not (entry and entry.final) then
          local file = files[path] or self.file_lines(path) or {}

          entry = { edit = Edit(diff, file), final = true, failed = false }
          self.entries[key] = entry
        end

        files[path] = entry.edit.whole and entry.edit.resolved.old_lines or nil
      end
    end
  end

  return self
end

function EditLog:_same(a, b)
  if #a ~= #b then return false end

  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end

  return true
end

function EditLog:changes(history)
  local before, paths = {}, {}

  self:prime(history)

  for _, tool in ipairs(EditLog.tools(history)) do
    for index, diff in ipairs(tool.diffs) do
      local path = diff.path

      if path and before[path] == nil then
        local edit = self:get(diff, tool.id .. ':' .. index, true)

        before[path] = edit.whole and edit.resolved.old_lines or false
        paths[#paths + 1] = path
      end
    end
  end

  local files = {}

  for _, path in ipairs(paths) do
    local old_lines = before[path]
    local new_lines = self.file_lines(path) or {}

    if old_lines and not self:_same(old_lines, new_lines) then
      files[#files + 1] = { filename = path, old_lines = old_lines, new_lines = new_lines }
    end
  end

  return files
end

function EditLog:_hunks(rows)
  local hunks, current = {}, nil

  for _, row in ipairs(rows) do
    if row.kind == 'hunk' then
      current = nil
    elseif EditLog.CHANGED[row.kind] then
      if not current then
        current = { line = row.new_lnum or row.old_lnum or 1, added = 0, removed = 0 }
        hunks[#hunks + 1] = current
      end

      current[EditLog.CHANGED[row.kind]] = current[EditLog.CHANGED[row.kind]] + 1
    end
  end

  return hunks
end

function EditLog:_prompt_before(history, index)
  for i = math.min(index, #history), 1, -1 do
    local event = history[i]

    if (event.kind == EVENT.prompt or event.kind == EVENT.user) and not event.steered then
      local text = vim.trim(context.strip(event.text or ''))

      return compact.line((text:match('^[^\n]*')), EditLog.PROMPT_WIDTH)
    end
  end
end

function EditLog:locations(history, tools)
  local items = {}

  self:prime(history)

  for _, tool in ipairs(tools) do
    local prompt = self:_prompt_before(history, tool.index)

    for index, diff in ipairs(tool.diffs) do
      local edit = self:get(diff, tool.id .. ':' .. index, true)
      local hunks = edit.whole and self:_hunks(edit:patch().rows) or {}

      if #hunks == 0 then
        local stat = edit:stat()
        hunks = { { line = 1, added = stat.added, removed = stat.removed } }
      end

      for _, hunk in ipairs(hunks) do
        items[#items + 1] = {
          path = diff.path,
          line = hunk.line,
          text = string.format('+%d −%d', hunk.added, hunk.removed) .. (prompt and ('  · ' .. prompt) or ''),
        }
      end
    end
  end

  return items
end

function EditLog:revert_plan(tools)
  local current, original, order = {}, {}, {}
  local skipped, undone = {}, 0

  local function text_of(path)
    if current[path] == nil then
      original[path] = self.file_lines(path) or {}
      current[path] = table.concat(original[path], '\n')
      order[#order + 1] = path
    end

    return current[path]
  end

  for t = #tools, 1, -1 do
    local diffs = tools[t].diffs or {}

    for d = #diffs, 1, -1 do
      local diff = diffs[d]
      local reverted, reason = Edit.undo(text_of(diff.path), diff)

      if reverted then
        current[diff.path] = reverted
        undone = undone + 1
      else
        skipped[#skipped + 1] = { path = diff.path, id = tools[t].id, reason = reason }
      end
    end
  end

  local files = {}

  for _, path in ipairs(order) do
    local lines = edit_text.lines_of(current[path])

    if table.concat(lines, '\n') ~= table.concat(original[path], '\n') then
      files[#files + 1] = { filename = path, old_lines = original[path], new_lines = lines }
    end
  end

  return { files = files, skipped = skipped, undone = undone }
end

return EditLog

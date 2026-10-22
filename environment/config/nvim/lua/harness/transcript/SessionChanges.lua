local EditLog = require('harness.transcript.EditLog')

local SessionChanges = {}

local function same(a, b)
  if #a ~= #b then return false end

  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end

  return true
end

function SessionChanges.files(history, edits, file_lines)
  local before, paths = {}, {}

  for _, tool in ipairs(EditLog.edits(history)) do
    for index, diff in ipairs(tool.diffs) do
      local path = diff.path

      if path and before[path] == nil then
        local edit = edits:get(diff, tool.id .. ':' .. index, true)

        before[path] = edit.whole and edit.resolved.old_lines or false
        paths[#paths + 1] = path
      end
    end
  end

  local files = {}

  for _, path in ipairs(paths) do
    local old_lines = before[path]
    local new_lines = file_lines(path) or {}

    if old_lines and not same(old_lines, new_lines) then
      files[#files + 1] = { filename = path, old_lines = old_lines, new_lines = new_lines }
    end
  end

  return files
end

return SessionChanges

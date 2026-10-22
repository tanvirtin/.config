local EditResolver = require('harness.transcript.EditResolver')

local Revert = {}

Revert.REASON = { changed = 'changed since', unknown = 'no record of what it replaced' }

local function trimmed(text)
  return ((text or ''):gsub('\n$', ''))
end

local function undo(text, diff)
  local old, new = trimmed(diff.old), trimmed(diff.new)

  if new == '' then return nil, Revert.REASON.unknown end
  if old == '' and text == new then return '' end

  local at = EditResolver.locate(text, new)

  if not at then return nil, Revert.REASON.changed end

  return EditResolver.replace(text, at, #new, old)
end

function Revert.plan(edits, file_lines)
  local current, original, order = {}, {}, {}
  local skipped, undone = {}, 0

  local function text_of(path)
    if current[path] == nil then
      original[path] = file_lines(path) or {}
      current[path] = table.concat(original[path], '\n')
      order[#order + 1] = path
    end

    return current[path]
  end

  for e = #edits, 1, -1 do
    local diffs = edits[e].diffs or {}

    for d = #diffs, 1, -1 do
      local diff = diffs[d]
      local reverted, reason = undo(text_of(diff.path), diff)

      if reverted then
        current[diff.path] = reverted
        undone = undone + 1
      else
        skipped[#skipped + 1] = { path = diff.path, id = edits[e].id, reason = reason }
      end
    end
  end

  local files = {}

  for _, path in ipairs(order) do
    local lines = EditResolver.lines_of(current[path])

    if table.concat(lines, '\n') ~= table.concat(original[path], '\n') then
      files[#files + 1] = { filename = path, old_lines = original[path], new_lines = lines }
    end
  end

  return { files = files, skipped = skipped, undone = undone }
end

return Revert

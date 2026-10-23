local compact = require('compact')
local context = require('harness.context')
local EVENT = require('harness.types.events').KIND

local EditLocations = {}

EditLocations.PROMPT_WIDTH = 60

local CHANGED = { add = 'added', remove = 'removed' }

local function hunks_of(rows)
  local hunks, current = {}, nil

  for _, row in ipairs(rows) do
    if row.kind == 'hunk' then
      current = nil
    elseif CHANGED[row.kind] then
      if not current then
        current = { line = row.new_lnum or row.old_lnum or 1, added = 0, removed = 0 }
        hunks[#hunks + 1] = current
      end

      current[CHANGED[row.kind]] = current[CHANGED[row.kind]] + 1
    end
  end

  return hunks
end

local function prompt_before(history, index)
  for i = math.min(index, #history), 1, -1 do
    local event = history[i]

    if (event.kind == EVENT.prompt or event.kind == EVENT.user) and not event.steered then
      local text = vim.trim(context.strip(event.text or ''))

      return compact.line((text:match('^[^\n]*')), EditLocations.PROMPT_WIDTH)
    end
  end
end

function EditLocations.items(history, edits, patches)
  local items = {}

  patches:prime(history)

  for _, edit in ipairs(edits) do
    local prompt = prompt_before(history, edit.index)

    for index, diff in ipairs(edit.diffs) do
      local resolved = patches:get(diff, edit.id .. ':' .. index, true)
      local hunks = resolved.whole and hunks_of(resolved:patch().rows) or {}

      if #hunks == 0 then
        local stat = resolved:stat()
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

return EditLocations

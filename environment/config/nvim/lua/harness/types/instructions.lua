local instructions = {}

local entries = {}

local function any(list, set)
  if not list or #list == 0 then return true end

  for _, value in ipairs(list) do
    if set and set[value] then return true end
  end

  return false
end

local function matches(entry, active)
  local when = entry.when

  if not when then return true end
  if not any(when.categories, active.categories) then return false end
  if not any(when.names, active.names) then return false end
  if not any(when.kinds, active.kinds) then return false end

  return true
end

function instructions.register(id, text, when)
  if type(id) ~= 'string' or id == '' then return end
  if type(text) ~= 'string' or text == '' then return end

  entries[id] = { text = text, when = when }
end

function instructions.unregister(id)
  entries[id] = nil
end

function instructions.text(active)
  active = active or {}

  local ids, seen, parts = {}, {}, {}

  for id in pairs(entries) do
    ids[#ids + 1] = id
  end

  table.sort(ids)

  for _, id in ipairs(ids) do
    local entry = entries[id]

    if matches(entry, active) and not seen[entry.text] then
      seen[entry.text] = true
      parts[#parts + 1] = entry.text
    end
  end

  return table.concat(parts, '\n')
end

function instructions.reset()
  entries = {}
end

return instructions

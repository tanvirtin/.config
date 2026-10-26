local content = {}

local entries = {}
local by_id = {}
local cache = setmetatable({}, { __mode = 'k' })

local fallback = {
  id = 'fallback',
  priority = -1000,
  render = { mode = 'raw' },
}

local function matches(def, block)
  if def.match then return def.match(block) and true or false end
  if def.kind and def.kind ~= block.kind then return false end
  if def.category and def.category ~= block.category then return false end
  if def.name and def.name ~= block.name then return false end

  return def.kind ~= nil or def.category ~= nil or def.name ~= nil
end

local function sort()
  table.sort(entries, function(a, b)
    local pa, pb = a.priority or 0, b.priority or 0

    if pa == pb then return a.id < b.id end

    return pa > pb
  end)
end

function content.register(def)
  assert(type(def) == 'table', 'content: definition must be a table')
  assert(type(def.id) == 'string' and def.id ~= '', 'content: definition needs an id')

  local existing = by_id[def.id]

  if existing then
    for i, entry in ipairs(entries) do
      if entry.id == def.id then
        entries[i] = def
        break
      end
    end
  else
    entries[#entries + 1] = def
  end

  by_id[def.id] = def
  sort()

  cache = setmetatable({}, { __mode = 'k' })

  return def
end

function content.get(id)
  return by_id[id]
end

function content.resolve(block)
  if not block then return fallback end

  local hit = cache[block]

  if hit then return hit end

  for _, def in ipairs(entries) do
    if matches(def, block) then
      cache[block] = def
      return def
    end
  end

  cache[block] = fallback

  return fallback
end

function content.mode(block)
  local def = content.resolve(block)

  return (def.render and def.render.mode) or 'raw'
end

function content.option(block, key)
  local def = content.resolve(block)

  return def.render and def.render[key]
end

function content.decorate(block, ctx)
  local def = content.resolve(block)

  return def.decorate and def.decorate(block, ctx) or nil
end

function content.actions(block)
  local def = content.resolve(block)

  return def.actions or {}
end

function content.instructions(block)
  local def = content.resolve(block)

  return def.instructions or {}
end

function content.reset()
  entries = {}
  by_id = {}
  cache = setmetatable({}, { __mode = 'k' })
end

content.FALLBACK = fallback

return content

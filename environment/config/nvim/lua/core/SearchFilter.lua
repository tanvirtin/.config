local lazy = require('core.lazy')

local Object = lazy('core.Object')

local SearchFilter = Object:extend()

SearchFilter.LIMIT = 2000
SearchFilter.BASENAME_BONUS = 1500
SearchFilter.BASENAME_START_BONUS = 500

function SearchFilter:constructor()
  return { _index = nil }
end

local function basename_start(label)
  local slash = label:match('.*()/')

  return slash and #(label:sub(1, slash)) or nil
end

local function to_bytes(label, positions)
  if not label:find('[\128-\255]') then return positions end

  local bytes = {}

  for i, char in ipairs(positions) do
    bytes[i] = vim.str_byteindex(label, 'utf-32', char)
  end

  return bytes
end

local function ranges(positions)
  local out = {}
  local from, to

  for _, byte in ipairs(positions) do
    if to and byte == to then
      to = byte + 1
    else
      if from then out[#out + 1] = { from, to } end
      from, to = byte, byte + 1
    end
  end

  if from then out[#out + 1] = { from, to } end

  return out
end

local function bonus(label, bytes)
  local start = basename_start(label)

  if not start or #bytes == 0 or bytes[1] < start then return 0 end

  return SearchFilter.BASENAME_BONUS + (bytes[1] == start and SearchFilter.BASENAME_START_BONUS or 0)
end

function SearchFilter:_index_of(items)
  local index = self._index

  if index and index.items == items and index.count == #items then return index end

  local labels, owners = {}, {}

  for i = 1, #items do
    local label = items[i].label or ''
    local list = owners[label]

    if not list then
      labels[#labels + 1] = label
      owners[label] = { i }
    else
      list[#list + 1] = i
    end
  end

  self._index = { items = items, count = #items, labels = labels, owners = owners }

  return self._index
end

function SearchFilter:match(items, query)
  if not items then return {}, {} end
  if not query or query == '' then return items, {} end

  local index = self:_index_of(items)
  local found = vim.fn.matchfuzzypos(index.labels, query:lower(), { limit = SearchFilter.LIMIT })
  local ranked = {}

  for i, label in ipairs(found[1]) do
    local bytes = to_bytes(label, found[2][i])

    ranked[i] = {
      label = label,
      score = found[3][i] + bonus(label, bytes),
      order = i,
      ranges = ranges(bytes),
    }
  end

  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.order < b.order
  end)

  local result, positions = {}, {}

  for _, entry in ipairs(ranked) do
    for _, owner in ipairs(index.owners[entry.label]) do
      result[#result + 1] = items[owner]
      positions[#result] = entry.ranges
    end
  end

  return result, positions
end

function SearchFilter:filter(items, query)
  return (self:match(items, query))
end

return SearchFilter

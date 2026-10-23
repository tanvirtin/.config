local fences = require('core.fences')
local Block = require('harness.transcript.Block')

local Layout = {}

function Layout.block_at(list, row)
  local low, high = 1, #list

  while low <= high do
    local mid = math.floor((low + high) / 2)
    local block = list[mid]

    if row < block.start then
      high = mid - 1
    elseif row >= block.finish then
      low = mid + 1
    else
      return block
    end
  end

  return list[#list]
end

local function same_lines(a, b)
  if #a ~= #b then return false end

  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end

  return true
end

function Layout.streaming(list, i)
  return i == #list and list[i].kind == Block.KIND.message
end

function Layout.first_changed(old, new)
  for i = 1, math.max(#old, #new) do
    local a, b = old[i], new[i]

    if not a or not b then return i end
    if a ~= b and (a.kind ~= b.kind or not same_lines(a.lines, b.lines)) then return i end
    if Layout.streaming(old, i) ~= Layout.streaming(new, i) then return i end
  end
end

function Layout.place(list, from, row)
  local lines, n = {}, 0

  for i = from, #list do
    local block = list[i]

    block.start = row + n

    for _, line in ipairs(block.lines) do
      n = n + 1
      lines[n] = line
    end

    if not Layout.streaming(list, i) then
      n = n + 1
      lines[n] = ''
    end

    block.finish = row + n
  end

  return lines
end

local function fenced(spans, index)
  for _, span in ipairs(spans) do
    if index > span[1] and index <= span[2] then return true end
  end

  return false
end

local function unquoted(lines)
  local out = {}

  for i, line in ipairs(lines) do
    if line:sub(1, 1) ~= '>' then return lines end

    out[i] = line:gsub('^> ?', '')
  end

  return out
end

function Layout.settled(lines, limit)
  lines = unquoted(lines)

  local spans, unclosed = fences.fences(lines)

  if unclosed then spans[#spans + 1] = { unclosed[1], math.huge } end

  for j = math.min(limit, #lines), 2, -1 do
    local line = lines[j]

    if lines[j - 1] == '' and line ~= '' and not line:find('^[%s|]') and not fenced(spans, j) then return j - 1 end
  end

  return 0
end

function Layout.prompt_above(list, row)
  if #list == 0 or row <= 0 then return nil end

  local block = Layout.block_at(list, row)

  for i = block and block.index or 0, 1, -1 do
    local candidate = list[i]

    if candidate.kind == Block.KIND.prompt and not candidate.steered then
      return candidate.start < row and candidate or nil
    end
  end
end

function Layout.signature(block)
  return table.concat({
    block.kind,
    tostring(block.status),
    tostring(block.finished),
    tostring(block.live),
    tostring(block.added),
    tostring(block.nested),
    tostring(block.last_child),
    tostring(block.tight),
    tostring(block.denied),
    tostring(block.interrupted),
  }, ':')
end

return Layout

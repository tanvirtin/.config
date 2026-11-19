local json_text = {}

local function skip(text, i)
  return text:find('[^%s]', i) or #text + 1
end

local function string_end(text, i)
  local j = i + 1

  while j <= #text do
    local c = text:sub(j, j)

    if c == '\\' then
      j = j + 2
    elseif c == '"' then
      return j
    else
      j = j + 1
    end
  end
end

local CLOSE = { ['{'] = '}', ['['] = ']' }

local function value_end(text, i)
  local c = text:sub(i, i)

  if c == '"' then return string_end(text, i) end

  if CLOSE[c] then
    local depth, j = 0, i

    while j <= #text do
      local d = text:sub(j, j)

      if d == '"' then
        j = string_end(text, j)
        if not j then return nil end
      elseif CLOSE[d] then
        depth = depth + 1
      elseif d == '}' or d == ']' then
        depth = depth - 1
        if depth == 0 then return j end
      end

      j = j + 1
    end

    return nil
  end

  local stop = text:find('[,%]}%s]', i)

  return stop and stop - 1 or #text
end

local function member(text, open, key)
  local i = skip(text, open + 1)

  while i <= #text and text:sub(i, i) ~= '}' do
    local key_end = string_end(text, i)

    if not key_end then return nil end

    local name = vim.json.decode(text:sub(i, key_end))

    i = skip(text, key_end + 1)
    if text:sub(i, i) ~= ':' then return nil end

    local start = skip(text, i + 1)
    local finish = value_end(text, start)

    if not finish then return nil end
    if name == key then return start, finish end

    i = skip(text, finish + 1)
    if text:sub(i, i) == ',' then i = skip(text, i + 1) end
  end
end

local function elements(text, open)
  local out = {}
  local i = skip(text, open + 1)

  while i <= #text and text:sub(i, i) ~= ']' do
    local finish = value_end(text, i)

    if not finish then return nil end

    out[#out + 1] = { start = i, finish = finish }
    i = skip(text, finish + 1)
    if text:sub(i, i) == ',' then i = skip(text, i + 1) end
  end

  return out, i
end

function json_text.remove(text, keys, value)
  local start = skip(text, 1)

  if text:sub(start, start) ~= '{' then return nil, 'the file is not a JSON object' end

  for index, key in ipairs(keys) do
    local found = member(text, start, key)

    if not found then return nil, string.format('the file has no "%s"', table.concat(keys, '.', 1, index)) end

    start = found
  end

  if text:sub(start, start) ~= '[' then return nil, string.format('"%s" is not a list', table.concat(keys, '.')) end

  local list, close = elements(text, start)

  if not list then return nil, 'the file is not valid JSON' end

  for n, element in ipairs(list) do
    local ok, decoded = pcall(vim.json.decode, text:sub(element.start, element.finish))

    if ok and decoded == value then
      if #list == 1 then return text:sub(1, start) .. text:sub(close) end
      if n < #list then return text:sub(1, element.start - 1) .. text:sub(list[n + 1].start) end

      return text:sub(1, list[n - 1].finish) .. text:sub(element.finish + 1)
    end
  end

  return nil, string.format('"%s" is not in "%s"', tostring(value), table.concat(keys, '.'))
end

return json_text

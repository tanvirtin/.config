local DiffLineCalculator = {}

DiffLineCalculator.HEADER_LINES = 2

local function hunk_start(line)
  local old, new = line:match('^@@ %-(%d+)[,%d]* %+(%d+)')

  return tonumber(old) or 0, tonumber(new) or 0
end

function DiffLineCalculator.numbers(lines)
  local numbers = {}
  local old_line, new_line = 0, 0

  for offset = DiffLineCalculator.HEADER_LINES + 1, #lines - 1 do
    local line = lines[offset]
    local mark = line:sub(1, 1)

    if mark == '@' then
      old_line, new_line = hunk_start(line)
      numbers[offset] = { mark = '@' }
    elseif mark == '+' then
      numbers[offset] = { mark = '+', number = new_line, new = new_line, old = old_line }
      new_line = new_line + 1
    elseif mark == '-' then
      numbers[offset] = { mark = '-', number = old_line, new = new_line, old = old_line }
      old_line = old_line + 1
    else
      numbers[offset] = { mark = ' ', number = new_line, new = new_line, old = old_line }
      old_line, new_line = old_line + 1, new_line + 1
    end
  end

  return numbers
end

local function find_sequence(haystack, needle)
  if #needle == 0 then return nil end

  for i = 1, #haystack - #needle + 1 do
    local found = true

    for j = 1, #needle do
      if haystack[i + j - 1] ~= needle[j] then
        found = false
        break
      end
    end

    if found then return i end
  end
end

local function side_of(block, numbers, skip)
  local lines, first = {}, nil

  for offset = DiffLineCalculator.HEADER_LINES + 1, #block.lines - 1 do
    local entry = numbers[offset]

    if entry and entry.mark == '@' and #lines > 0 then break end

    if entry and entry.mark ~= '@' and entry.mark ~= skip then
      first = first or (skip == '-' and entry.new or entry.old)
      lines[#lines + 1] = block.lines[offset]:sub(2)
    end
  end

  return lines, first
end

function DiffLineCalculator.offset(block, file_lines, cache)
  if not block.path then return nil end

  local key = block.path .. '\0' .. table.concat(block.lines, '\n')

  if cache and cache[key] then return cache[key] end

  local numbers = DiffLineCalculator.numbers(block.lines)
  local file = file_lines(block.path)

  for _, skip in ipairs({ '-', '+' }) do
    local lines, first = side_of(block, numbers, skip)
    local found = first and find_sequence(file, lines)

    if found then
      if skip == '-' and cache then cache[key] = found - first end
      return found - first
    end
  end
end

function DiffLineCalculator.line(block, row, offset)
  local entry = DiffLineCalculator.numbers(block.lines)[row - block.start + 1]

  return entry and entry.new and offset and entry.new + offset or nil
end

return DiffLineCalculator

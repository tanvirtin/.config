local fences = {}

local function fence_marks(line)
  local marks, rest = line:match('^ ? ? ?(```+)(.*)$')

  if not marks then
    marks, rest = line:match('^ ? ? ?(~~~+)(.*)$')
  end

  return marks, rest
end

function fences.fence_for(lines)
  local longest = 0

  for _, line in ipairs(lines) do
    local run = line:match('^ ? ? ?(`+)')

    if run and #run > longest then longest = #run end
  end

  return string.rep('`', math.max(3, longest + 1))
end

function fences.fences(lines)
  local spans, open, start = {}, nil, nil

  for i, line in ipairs(lines) do
    local marks, rest = fence_marks(line)

    if marks then
      if not open then
        open, start = marks, i
      elseif marks:sub(1, 1) == open:sub(1, 1) and #marks >= #open and vim.trim(rest) == '' then
        spans[#spans + 1] = { start, i }
        open = nil
      end
    end
  end

  return spans, open and { start, nil, open } or nil
end

function fences.fenced_at(lines, index)
  local spans, unclosed = fences.fences(lines)

  if unclosed then spans[#spans + 1] = { unclosed[1], #lines + 1 } end

  for _, span in ipairs(spans) do
    if index > span[1] and index < span[2] then return span[1] + 1, span[2] - 1 end
  end
end

function fences.open(lines)
  local _, unclosed = fences.fences(lines)

  return unclosed and unclosed[3] or nil
end

return fences

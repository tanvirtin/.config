local fences = require('core.fences')
local Block = require('harness.transcript.Block')

local CodeBlocks = {}

local function language_of(line)
  return line:match('^%s*[`~]+%s*([%w_.+-]*)') or ''
end

local function dedent(lines, indent)
  local out = {}

  for i, line in ipairs(lines) do
    local leading = #line:match('^ *')

    out[i] = line:sub(math.min(leading, indent) + 1)
  end

  return out
end

local function span_of(block, from, to, open)
  local opening = block.lines[from]
  local body = {}

  for i = from + 1, to - 1 do
    body[#body + 1] = block.lines[i]
  end

  return {
    start = block.start + from - 1,
    finish = block.start + to - (open and 2 or 1),
    body_start = block.start + from,
    body_finish = block.start + to - 2,
    language = language_of(opening),
    lines = dedent(body, #opening:match('^ *')),
  }
end

function CodeBlocks.list(blocks)
  local list = {}

  for _, block in ipairs(blocks) do
    if block.kind == Block.KIND.message and block.start then
      local spans, unclosed = fences.fences(block.lines)

      for _, span in ipairs(spans) do
        list[#list + 1] = span_of(block, span[1], span[2])
      end

      if unclosed then list[#list + 1] = span_of(block, unclosed[1], #block.lines + 1, true) end
    end
  end

  table.sort(list, function(a, b)
    return a.start < b.start
  end)

  return list
end

function CodeBlocks.at(list, row)
  for _, span in ipairs(list) do
    if row >= span.start and row <= span.finish then return span end
  end
end

function CodeBlocks.next(list, row, count)
  local seen = 0

  for _, span in ipairs(list) do
    if span.start > row then
      seen = seen + 1
      if seen == (count or 1) then return span end
    end
  end
end

function CodeBlocks.previous(list, row, count)
  local seen = 0

  for i = #list, 1, -1 do
    local span = list[i]

    if span.body_start < row then
      seen = seen + 1
      if seen == (count or 1) then return span end
    end
  end
end

return CodeBlocks

local Buffer = require('core.editor.Buffer')
local outline = require('nvim_mcp.outline')

local spots = {}

spots.SCHEME = 'nvim://file/'

function spots.parse(at, previous)
  at = vim.trim(at or '')

  if vim.startswith(at, spots.SCHEME) then at = at:sub(#spots.SCHEME + 1) end

  local path, rest = at:match('^(.-)#(.+)$')
  local spot

  if path then
    local from, to = rest:match('^L(%d+)%-L?(%d+)$')

    from = from or rest:match('^L(%d+)$')

    spot = from and { path = path, from = tonumber(from), to = tonumber(to) } or { path = path, symbol = rest }
  else
    local file, from, to = at:match('^(.-):(%d+)%-(%d+)$')

    if not file then
      file, from = at:match('^(.-):(%d+)$')
    end

    spot = { path = file or at, from = tonumber(from), to = tonumber(to) }
  end

  if spot.path == '' then spot.path = previous end

  if not spot.path then return nil, 'no file in "' .. at .. '" and no spot before it' end

  return spot
end

function spots.resolve(spot, buf)
  local buffer = Buffer(buf)
  local last = buffer:get_line_count()

  if spot.symbol then
    local first, final, note = outline.span(buffer, spot.symbol)

    if not first then return nil, note end

    return { from = first, to = final, note = note }
  end

  local from = math.min(spot.from or 1, last)

  return { from = from, to = math.max(from, math.min(spot.to or from, last)) }
end

return spots

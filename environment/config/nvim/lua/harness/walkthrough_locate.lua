local symbols = require('harness.symbols')
local walkthrough_type = require('harness.types.walkthrough')

local walkthrough_locate = {}

local function hunk(id, scope)
  if not scope then return nil, id .. ': hunk ids come from walkthrough_scope; call it first' end

  local entry = scope.by_id[id]

  if not entry then return nil, 'no hunk ' .. id end

  return { path = entry.file.absolute, line = entry.hunk.first, end_line = entry.hunk.last }
end

function walkthrough_locate.resolve(text, env)
  if type(text) ~= 'string' or vim.trim(text) == '' then return nil, 'an empty location' end

  text = vim.trim(text)

  if text:match('^h%d+$') then return hunk(text, env.scope) end

  local path, rest = text:match('^([^:]+):(.+)$')

  path = path or text

  local first, last = (rest or ''):match('^(%d+)%-?(%d*)$')

  if first then
    return { path = path, line = tonumber(first), end_line = last ~= '' and tonumber(last) or tonumber(first) }
  end

  local lines = env.read(walkthrough_type.absolute(path, env.dir))

  if not lines then return nil, 'no file ' .. path end

  if not rest then return { path = path, line = 1, end_line = math.max(#lines, 1) } end

  local symbol, err = symbols.find(symbols.parse(lines, path), rest)

  if not symbol then return nil, string.format('%s: %s', path, err) end

  return { path = path, line = symbol.first, end_line = symbol.last }
end

function walkthrough_locate.ranges(list, env)
  local ranges = {}

  for index, text in ipairs(list or {}) do
    local range, err = walkthrough_locate.resolve(text, env)

    if not range then return nil, #list > 1 and string.format('at %d: %s', index, err) or err end

    ranges[index] = range
  end

  if #ranges == 0 then return nil, 'a step needs at' end

  return ranges
end

return walkthrough_locate

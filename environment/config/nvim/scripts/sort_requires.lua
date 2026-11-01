local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

local function wanted(line)
  return line:match('^local [%w_, ]+ = require%(') or line:match('^local [%w_, ]+ = lazy%(')
end

local function sorted(block)
  local head = block[1] == 'local lazy = require(\'core.lazy\')' and table.remove(block, 1) or nil
  local order = {}

  for index, line in ipairs(block) do
    order[line] = order[line] or index
  end

  table.sort(block, function(a, b)
    if #a ~= #b then return #a < #b end

    return order[a] < order[b]
  end)

  if head then
    local shorter = false

    for _, line in ipairs(block) do
      shorter = shorter or #line < #head
    end

    if shorter then table.insert(block, 1, '') end

    table.insert(block, 1, head)
  end

  return block
end

local function fix(source)
  local out, block = {}, {}

  local function flush()
    vim.list_extend(out, sorted(block))
    block = {}
  end

  for _, line in ipairs(vim.split(source, '\n', { plain = true })) do
    if wanted(line) then
      block[#block + 1] = line
    else
      flush()
      out[#out + 1] = line
    end
  end

  flush()

  return table.concat(out, '\n')
end

local changed = 0

for _, path in ipairs(vim.fn.glob(root .. '/lua/harness/**/*.lua', false, true)) do
  if path:match('_spec%.lua$') then goto continue end

  local file = assert(io.open(path, 'r'))
  local source = file:read('*a')

  file:close()

  local fixed = fix(source)

  if fixed ~= source then
    local out = assert(io.open(path, 'w'))

    out:write(fixed)
    out:close()
    changed = changed + 1
    print('sorted ' .. path:sub(#root + 2))
  end

  ::continue::
end

print(string.format('%d file%s changed', changed, changed == 1 and '' or 's'))

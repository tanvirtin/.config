local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local mapping_path = arg[1]

if not mapping_path then
  io.stderr:write('usage: nvim -l scripts/move_modules.lua <mapping.lua>\n')
  os.exit(1)
end

local mapping = dofile(mapping_path)

local function tree(module)
  if module == 'harness' or module:match('^harness%.') then return '/harness/lua/' end

  return '/lua/'
end

local function file_of(module)
  local base = root .. tree(module) .. module:gsub('%.', '/')

  if vim.fn.filereadable(base .. '.lua') == 1 then return base .. '.lua', 'file' end
  if vim.fn.isdirectory(base) == 1 then return base, 'dir' end
end

local function destination(module)
  local init = module:match('^(.*)%.init$')

  if init then return root .. tree(init) .. init:gsub('%.', '/') .. '/init.lua', init end

  return root .. tree(module) .. module:gsub('%.', '/') .. '.lua', module
end

local function run(cmd)
  local result = vim.system(cmd, { cwd = root, text = true }):wait()

  if result.code ~= 0 then
    io.stderr:write(table.concat(cmd, ' ') .. '\n' .. (result.stderr or '') .. '\n')
    os.exit(1)
  end
end

local function move(from, to)
  vim.fn.mkdir(vim.fn.fnamemodify(to, ':h'), 'p')
  run({ 'git', 'mv', from, to })
end

local renames = {}

local olds = vim.tbl_keys(mapping)

table.sort(olds, function(a, b)
  return #a > #b
end)

for _, old in ipairs(olds) do
  local new = mapping[old]
  local from, kind = file_of(old)

  if not from then
    io.stderr:write('no module ' .. old .. '\n')
    os.exit(1)
  end

  if kind == 'dir' then
    move(from, root .. tree(new) .. new:gsub('%.', '/'))
    renames[#renames + 1] = { old = old, new = new, prefix = true }
  else
    local to, module = destination(new)
    local spec = from:gsub('%.lua$', '_spec.lua')

    move(from, to)

    if vim.fn.filereadable(spec) == 1 then
      local spec_to = to:match('/init%.lua$') and to:gsub('/init%.lua$', '_spec.lua') or to:gsub('%.lua$', '_spec.lua')

      move(spec, spec_to)
    end

    renames[#renames + 1] = { old = old, new = module }
  end
end

table.sort(renames, function(a, b)
  return #a.old > #b.old
end)

local function resolve(name)
  for _, rename in ipairs(renames) do
    if name == rename.old then return rename.new end
    if rename.prefix and name:sub(1, #rename.old + 1) == rename.old .. '.' then
      return rename.new .. name:sub(#rename.old + 1)
    end
  end

  return name
end

local PATTERNS = {
  '(require%s*%(?%s*)([\'"])([%w_%.]+)%2',
  '(lazy%(%s*)([\'"])([%w_%.]+)%2',
  '(pcall%(%s*require%s*,%s*)([\'"])([%w_%.]+)%2',
  '(package%.loaded%[%s*)([\'"])([%w_%.]+)%2',
}

local changed = 0

for _, dir in ipairs({ 'lua', 'harness/lua', 'scripts', 'bench' }) do
  for _, path in ipairs(vim.fn.globpath(root .. '/' .. dir, '**/*.lua', false, true)) do
    local text = table.concat(vim.fn.readfile(path, 'b'), '\n')
    local out = text

    for _, pattern in ipairs(PATTERNS) do
      out = out:gsub(pattern, function(head, quote, name)
        return head .. quote .. resolve(name) .. quote
      end)
    end

    out = out:gsub('(require\\)([\'"])([%w_%.]+)\\%2', function(head, quote, name)
      return head .. quote .. resolve(name) .. '\\' .. quote
    end)

    if out ~= text then
      vim.fn.writefile(vim.split(out, '\n', { plain = true }), path, 'b')
      changed = changed + 1
    end
  end
end

run({ 'nvim', '-l', 'scripts/sort_requires.lua' })
run({ 'stylua', '--config-path', 'stylua.toml', 'lua', 'harness/lua', 'scripts' })

print(string.format('moved %d modules, rewrote %d files', #renames, changed))

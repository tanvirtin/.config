local eq = assert.are.same

local ROOT = 'lua/sn'

local NEOVIM = {
  'api',
  'fn',
  'bo',
  'wo',
  'cmd',
  'uv',
  'loop',
  'keymap',
  'treesitter',
  'v',
  'o',
  'g',
  'b',
  'w',
  'schedule',
  'schedule_wrap',
  'defer_fn',
  'notify',
  'ui',
  'wait',
  'system',
  'filetype',
  'keycode',
}

local UTILITY = {
  NIL = true,
  deep_equal = true,
  deepcopy = true,
  empty_dict = true,
  inspect = true,
  json = true,
  list_extend = true,
  list_slice = true,
  pesc = true,
  split = true,
  startswith = true,
  tbl_contains = true,
  tbl_extend = true,
  tbl_filter = true,
  tbl_keys = true,
  tbl_map = true,
  trim = true,
}

local NEOVIM_SET = {}

for _, name in ipairs(NEOVIM) do
  NEOVIM_SET[name] = true
end

local LAYERS = {
  { 'sn.types', 1 },
  { 'sn.async', 1 },
  { 'sn.settings', 1 },
  { 'sn.vgit', 1 },
  { 'sn.context', 2 },
  { 'sn.agent', 2 },
  { 'sn.servers', 2 },
  { 'sn.connection', 2 },
  { 'sn.permissions', 2 },
  { 'sn.permission_rules', 2 },
  { 'sn.session.Session', 3 },
  { 'sn.session', 3 },
  { 'sn.edits', 3 },
  { 'sn.session.Workspace', 4 },
  { 'sn.session.store', 4 },
  { 'sn.session.hub', 5 },
  { 'sn.session.SessionHub', 5 },
  { 'sn.session.Admission', 5 },
  { 'sn.tools', 6 },
  { 'sn.follow', 6 },
  { 'sn.client', 6 },
  { 'sn.features', 6 },
  { 'sn.transcript', 6 },
  { 'sn.transcript.view', 7 },
  { 'sn.transcript.effects', 7 },
  { 'sn.ui', 7 },
  { 'sn.composer', 7 },
  { 'sn.asks', 7 },
  { 'sn.picker', 7 },
  { 'sn.cli', 8 },
  { 'sn', 8 },
}

local WIRE = {
  'sessionUpdate',
  'toolCallId',
  'rawInput',
  'optionId',
  '_meta',
  '\'session/',
  'jsonrpc',
  'stopReason',
  'configOptions',
  'sessionId',
  'agentCapabilities',
  'promptCapabilities',
}

local NEOVIM_ALLOWED = {}

local UPWARD_ALLOWED = {}

local UI = { 'sn.transcript', 'sn.composer', 'sn.asks', 'sn.picker', 'sn.ui' }

local DOMAIN = {
  'sn.session',
  'sn.agent',
  'sn.follow',
  'sn.permissions',
  'sn.permission_rules',
  'sn.edits',
  'sn.servers',
  'sn.tools',
  'sn.connection',
}

local function modules()
  local out = {}

  for _, path in ipairs(vim.fn.globpath(ROOT, '**/*.lua', false, true)) do
    if not path:match('_spec%.lua$') then
      local name = path:gsub('^lua/', ''):gsub('%.lua$', ''):gsub('/init$', ''):gsub('/', '.')
      out[#out + 1] = { name = name, path = path, source = table.concat(vim.fn.readfile(path), '\n') }
    end
  end

  table.sort(out, function(a, b)
    return a.name < b.name
  end)

  return out
end

local function file_name(module)
  return vim.fs.basename(module.path):gsub('%.lua$', '')
end

local function pascal(module)
  return file_name(module):match('^%u') ~= nil
end

local function defines_class(source)
  return source:find('\nlocal [%w_]+ = [%w_.]+:extend%(%)') ~= nil or source:find('dataclass%.define%(') ~= nil
end

local function returns_class(source)
  local returned = source:match('\nreturn ([%w_]+)%s*$')

  return returned ~= nil and source:find('\nlocal ' .. returned .. ' = [%w_.]+:extend%(%)') ~= nil
end

local function require_blocks(source)
  local blocks, block = {}, {}

  for line in (source .. '\n'):gmatch('(.-)\n') do
    if line:match('^local [%w_, ]+ = require%(') or line:match('^local [%w_, ]+ = lazy%(') then
      block[#block + 1] = line
    elseif #block > 0 then
      blocks[#blocks + 1] = block
      block = {}
    end
  end

  return blocks
end

local function neovim_calls(source)
  local count = 0

  for line in (source .. '\n'):gmatch('(.-)\n') do
    for _, name in ipairs(NEOVIM) do
      if line:find('vim%.' .. name .. '[%.%[%(]') then
        count = count + 1
        break
      end
    end
  end

  return count
end

local function rank(name)
  local best, length = nil, -1

  for _, layer in ipairs(LAYERS) do
    local prefix = layer[1]

    if (name == prefix or name:sub(1, #prefix + 1) == prefix .. '.') and #prefix > length then
      best, length = layer[2], #prefix
    end
  end

  return best
end

local function upward(module)
  local out = {}
  local own = rank(module.name)

  for _, target in module.source:gmatch('(require|lazy)%(\'(sn[%w_.]*)\'%)') do
    local theirs = rank(target)

    if own and theirs and theirs > own then out[#out + 1] = module.name .. ' -> ' .. target end
  end

  return out
end

describe('sn architecture:', function()
  it('calls Neovim only through core and ui, and only ever less than before', function()
    local over = {}

    for _, module in ipairs(modules()) do
      local count = neovim_calls(module.source)
      local allowed = NEOVIM_ALLOWED[module.name] or 0

      if count > allowed then
        over[#over + 1] = string.format('%s: %d vim.* calls (allowed %d)', module.name, count, allowed)
      end
    end

    eq({}, over)
  end)

  it('keeps the allowlist tight, so every removal is locked in', function()
    local loose = {}

    for _, module in ipairs(modules()) do
      local allowed = NEOVIM_ALLOWED[module.name]
      local count = neovim_calls(module.source)

      if allowed and count < allowed then
        loose[#loose + 1] = string.format('%s: allowed %d, now %d', module.name, allowed, count)
      end
    end

    eq({}, loose)
  end)

  it('uses only approved Neovim helpers outside core and ui', function()
    local found = {}

    for _, module in ipairs(modules()) do
      for name in module.source:gmatch('vim%.([%w_]+)') do
        if not NEOVIM_SET[name] and not UTILITY[name] then found[#found + 1] = module.name .. ': vim.' .. name end
      end
    end

    eq({}, found)
  end)

  it('only requires its own layer or lower ones', function()
    local found = {}

    for _, module in ipairs(modules()) do
      for _, edge in ipairs(upward(module)) do
        if not UPWARD_ALLOWED[edge] then found[#found + 1] = edge end
      end
    end

    eq({}, found)
  end)

  it('lists only upward requires that still exist', function()
    local present = {}

    for _, module in ipairs(modules()) do
      for _, edge in ipairs(upward(module)) do
        present[edge] = true
      end
    end

    local stale = {}

    for edge in pairs(UPWARD_ALLOWED) do
      if not present[edge] then stale[#stale + 1] = edge end
    end

    table.sort(stale)
    eq({}, stale)
  end)

  it('has no module cycles', function()
    local graph, names = {}, {}

    for _, module in ipairs(modules()) do
      names[module.name] = true
      graph[module.name] = {}
    end

    for _, module in ipairs(modules()) do
      for _, target in module.source:gmatch('(require|lazy)%(\'(sn[%w_.]*)\'%)') do
        if names[target] then graph[module.name][#graph[module.name] + 1] = target end
      end
    end

    local visiting, done, found = {}, {}, {}

    local function visit(name, path)
      if done[name] then return end
      if visiting[name] then
        found[#found + 1] = table.concat(path, ' -> ') .. ' -> ' .. name
        return
      end

      visiting[name] = true
      path[#path + 1] = name

      for _, target in ipairs(graph[name]) do
        visit(target, path)
      end

      path[#path] = nil
      visiting[name] = nil
      done[name] = true
    end

    for name in pairs(graph) do
      visit(name, {})
    end

    eq({}, found)
  end)

  it('reaches a server only through sn.servers', function()
    local found = {}

    for _, module in ipairs(modules()) do
      if module.name:sub(1, #'sn.servers') ~= 'sn.servers' then
        for target in module.source:gmatch('require%(\'(sn%.servers%.[%w_.]+)\'%)') do
          found[#found + 1] = module.name .. ' -> ' .. target
        end
      end
    end

    eq({}, found)
  end)

  it('speaks no wire protocol outside its server', function()
    local found = {}

    for _, module in ipairs(modules()) do
      if not module.name:find('^sn%.servers%.') then
        for _, word in ipairs(WIRE) do
          if module.source:find(word, 1, true) then found[#found + 1] = module.name .. ': ' .. word end
        end
      end
    end

    eq({}, found)
  end)

  it('talks to vgit only through sn.vgit', function()
    local found = {}

    for _, module in ipairs(modules()) do
      if module.name ~= 'sn.vgit' and module.source:find('[\'"]vgit[%.\'"]') then found[#found + 1] = module.name end
    end

    eq({}, found)
  end)

  it('lets the UI reach the session domain only through sn.client', function()
    local found = {}

    for _, module in ipairs(modules()) do
      local ui = false

      for _, prefix in ipairs(UI) do
        ui = ui or module.name == prefix or module.name:sub(1, #prefix + 1) == prefix .. '.'
      end

      if ui then
        for target in module.source:gmatch('[%(]%s*\'(sn%.[%w_.]+)\'') do
          for _, domain in ipairs(DOMAIN) do
            if target == domain or target:sub(1, #domain + 1) == domain .. '.' then
              found[#found + 1] = module.name .. ' -> ' .. target
            end
          end
        end
      end
    end

    eq({}, found)
  end)

  it('places every sn module in a layer', function()
    local unranked = {}

    for _, module in ipairs(modules()) do
      if not rank(module.name) then unranked[#unranked + 1] = module.name end
    end

    eq({}, unranked)
  end)

  it('defines a class in every PascalCase file, as vgit names them', function()
    local found = {}

    for _, module in ipairs(modules()) do
      if pascal(module) and not module.name:find('%.calculators%.') and not defines_class(module.source) then
        found[#found + 1] = module.name
      end
    end

    eq({}, found)
  end)

  it('names every file that returns a class in PascalCase', function()
    local found = {}

    for _, module in ipairs(modules()) do
      if not pascal(module) and returns_class(module.source) then found[#found + 1] = module.name end
    end

    eq({}, found)
  end)

  it('orders its requires by length, shortest first', function()
    local found = {}

    for _, module in ipairs(modules()) do
      for _, block in ipairs(require_blocks(module.source)) do
        for i = 2, #block do
          if #block[i] < #block[i - 1] then found[#found + 1] = module.name .. ': ' .. block[i] end
        end
      end
    end

    eq({}, found)
  end)

  it('requires every sn module by its exact name', function()
    local names, found = {}, {}

    for _, module in ipairs(modules()) do
      names[module.name] = true
    end

    for _, module in ipairs(modules()) do
      for _, call in ipairs({ 'require', 'lazy' }) do
        for target in module.source:gmatch('%f[%w]' .. call .. '%(\'(sn[%w_.]*)\'%)') do
          if not names[target] then found[#found + 1] = module.name .. ' -> ' .. target end
        end
      end
    end

    eq({}, found)
  end)
end)

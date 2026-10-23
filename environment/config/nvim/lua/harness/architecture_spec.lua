local eq = assert.are.same

local ROOT = 'lua/harness'

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

local LAYERS = {
  { 'harness.types', 1 },
  { 'harness.async', 1 },
  { 'harness.settings', 1 },
  { 'harness.vgit', 1 },
  { 'harness.events', 2 },
  { 'harness.context', 2 },
  { 'harness.agent', 2 },
  { 'harness.servers', 2 },
  { 'harness.permissions', 2 },
  { 'harness.session', 3 },
  { 'harness.workspace', 4 },
  { 'harness.session_store', 4 },
  { 'harness.hub', 5 },
  { 'harness.tools', 6 },
  { 'harness.follow', 6 },
  { 'harness.features', 6 },
  { 'harness.transcript', 6 },
  { 'harness.ui', 7 },
  { 'harness.cli', 8 },
  { 'harness', 8 },
}

local NEOVIM_ALLOWED = {}

local UPWARD_ALLOWED = {}

local function modules()
  local out = {}

  for _, path in ipairs(vim.fn.globpath(ROOT, '**/*.lua', false, true)) do
    if not path:match('_spec%.lua$') then
      local name = path:gsub('^lua/', ''):gsub('%.lua$', ''):gsub('/init$', ''):gsub('/', '.')
      out[#out + 1] = { name = name, source = table.concat(vim.fn.readfile(path), '\n') }
    end
  end

  table.sort(out, function(a, b)
    return a.name < b.name
  end)

  return out
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

  for target in module.source:gmatch('require%(\'(harness[%w_.]*)\'%)') do
    local theirs = rank(target)

    if own and theirs and theirs > own then out[#out + 1] = module.name .. ' -> ' .. target end
  end

  return out
end

describe('harness architecture:', function()
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

  it('talks to vgit only through harness.vgit', function()
    local found = {}

    for _, module in ipairs(modules()) do
      if module.name ~= 'harness.vgit' and module.source:find('[\'"]vgit[%.\'"]') then
        found[#found + 1] = module.name
      end
    end

    eq({}, found)
  end)

  it('places every harness module in a layer', function()
    local unranked = {}

    for _, module in ipairs(modules()) do
      if not rank(module.name) then unranked[#unranked + 1] = module.name end
    end

    eq({}, unranked)
  end)
end)

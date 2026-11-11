local eq = assert.are.same

local ROOTS = { 'lua/nvim_mcp', 'lua/surfaces', 'lua/sources', 'lua/ui' }

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
  'lsp',
  'diagnostic',
  'uri_from_bufnr',
  'uri_to_fname',
  'rpcrequest',
  'fs',
  'env',
  'iter',
}

local RAW_BY_DESIGN = {
  ['lua/nvim_mcp/script.lua'] = 'wraps the raw API to track what a script creates',
  ['lua/nvim_mcp/server.lua'] = 'runs in the headless child Neovim as the RPC bridge',
  ['lua/nvim_mcp/run.lua'] = 'starts the bridge in the child Neovim',
  ['lua/ui/Extmark.lua'] = 'is the extmark wrapper, as it is in vgit',
  ['lua/ui/assertions.lua'] = 'reads real editor state so specs can assert on it',
  ['lua/ui/mount.lua'] = 'mounts and tears down real windows for specs',
}

local function calls(path)
  local found = {}

  for number, line in ipairs(vim.fn.readfile(path)) do
    for _, name in ipairs(NEOVIM) do
      if line:find('vim%.' .. name .. '[%.%[%(]') then
        found[#found + 1] = string.format('%s:%d', path, number)
        break
      end
    end
  end

  return found
end

describe('the editor tools, surfaces, sources and ui:', function()
  it('reach Neovim through core, except where the file exists to be raw', function()
    local raw = {}

    for _, root in ipairs(ROOTS) do
      for _, path in ipairs(vim.fn.globpath(root, '**/*.lua', false, true)) do
        if not path:match('_spec%.lua$') and not RAW_BY_DESIGN[path] then vim.list_extend(raw, calls(path)) end
      end
    end

    eq({}, raw)
  end)

  it('names only files that exist in the raw-by-design list', function()
    local missing = {}

    for path in pairs(RAW_BY_DESIGN) do
      if vim.fn.filereadable(path) ~= 1 then missing[#missing + 1] = path end
    end

    eq({}, missing)
  end)
end)

local fs = require('core.fs')
local sources = require('sources')

local function cwd(opts)
  return fs.normalize(opts.cwd or fs.local_cwd())
end

return {
  name = 'files',
  description = 'Files under the cwd (or path), .gitignore respected; query fuzzy-matches the path.',
  collect = function(query, opts, emit, done)
    local root = cwd(opts)
    local items = {}

    local function parse(line)
      return { kind = 'file', path = root .. '/' .. line, label = line }
    end

    return sources.lines({ 'rg', '--files', '--hidden', '--glob', '!.git' }, { cwd = root }, parse, function(batch)
      if query == '' then return emit(batch) end
      vim.list_extend(items, batch)
    end, function(err)
      if query ~= '' then emit(sources.filter(items, query)) end
      done(err)
    end)
  end,
}

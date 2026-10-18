local sources = {}

local registry = {}

function sources.register(source)
  assert(type(source.name) == 'string', 'a source needs a name')
  assert(type(source.collect) == 'function', 'a source needs collect')

  registry[source.name] = source

  return source
end

local BUILTIN = { 'files', 'grep', 'lsp', 'diagnostics', 'buffers' }

local loaded = false

local function load()
  if loaded then return end

  loaded = true

  for _, name in ipairs(BUILTIN) do
    sources.register(require('sources.' .. name))
  end
end

function sources.get(name)
  load()

  return registry[name]
end

function sources.names()
  load()

  local names = vim.tbl_keys(registry)

  table.sort(names)

  return names
end

function sources.collect(name, query, opts, timeout_ms)
  local source = sources.get(name)

  if not source then return {}, 'unknown source: ' .. tostring(name) end

  local items, finished, failure = {}, false, nil
  local cancel = source.collect(query or '', opts or {}, function(batch)
    vim.list_extend(items, batch)
  end, function(err)
    failure = err
    finished = true
  end)

  vim.wait(timeout_ms or 10000, function()
    return finished
  end, 10)

  if not finished then
    if cancel then cancel() end
    failure = 'timed out; showing what arrived'
  end

  return items, failure
end

function sources.filter(items, query)
  if not query or query == '' then return items end

  return vim.fn.matchfuzzy(items, query, {
    text_cb = function(item)
      return item.label or item.path or ''
    end,
  })
end

function sources.lines(cmd, opts, parse, emit, done)
  local pending = ''
  local cancelled = false

  local function flush(chunk, final)
    local text = pending .. (chunk or '')
    local lines = vim.split(text, '\n', { plain = true })

    pending = final and '' or table.remove(lines)

    local batch = {}

    for _, line in ipairs(lines) do
      if line ~= '' then
        local item = parse(line)
        if item then batch[#batch + 1] = item end
      end
    end

    if #batch > 0 then vim.schedule(function()
      if not cancelled then emit(batch) end
    end) end
  end

  local ok, proc = pcall(vim.system, cmd, {
    cwd = opts.cwd,
    text = true,
    stdout = function(_, chunk)
      if chunk then flush(chunk, false) end
    end,
  }, function(out)
    flush(nil, true)
    vim.schedule(function()
      if cancelled then return end
      done((out.code ~= 0 and out.code ~= 1 and out.signal == 0) and vim.trim(out.stderr or '') or nil)
    end)
  end)

  if not ok then
    vim.schedule(function()
      done(tostring(proc))
    end)
    return function() end
  end

  return function()
    cancelled = true
    pcall(proc.kill, proc, 15)
  end
end

return sources

local sources = require('sources')

return {
  name = 'grep',
  description = 'Lines matching a regex under the cwd (or path); smart case, .gitignore respected.',
  live = true,
  collect = function(query, opts, emit, done)
    if query == '' then
      vim.schedule(done)
      return function() end
    end

    local root = vim.fs.normalize(opts.cwd or vim.fn.getcwd())
    local cmd = { 'rg', '--vimgrep', '--smart-case', '--max-columns=300', '--max-columns-preview', '--', query }

    if opts.path then cmd[#cmd + 1] = opts.path end

    local last

    return sources.lines(cmd, { cwd = root }, function(line)
      local path, lnum, col, text = line:match('^(.-):(%d+):(%d+):(.*)$')

      if not path or (path .. ':' .. lnum) == last then return nil end

      last = path .. ':' .. lnum

      local absolute = path:sub(1, 1) == '/' and path or (root .. '/' .. path)

      return {
        kind = 'match',
        path = absolute,
        line = tonumber(lnum),
        col = tonumber(col),
        text = text,
        label = string.format('%s:%s  %s', path, lnum, vim.trim(text)),
      }
    end, emit, done)
  end,
}

local SEVERITY = { 'ERROR', 'WARN', 'INFO', 'HINT' }

return {
  name = 'diagnostics',
  description = 'LSP and linter diagnostics, errors first; query fuzzy-matches the message.',
  collect = function(query, opts, emit, done)
    local items = {}

    for _, d in ipairs(vim.diagnostic.get(opts.buf)) do
      local path = vim.api.nvim_buf_get_name(d.bufnr)
      local severity = SEVERITY[d.severity] or tostring(d.severity)

      items[#items + 1] = {
        kind = 'diagnostic',
        path = path ~= '' and path or nil,
        line = d.lnum + 1,
        col = d.col + 1,
        text = string.format('%s %s%s', severity, d.message, d.source and (' [' .. d.source .. ']') or ''),
        label = string.format('%s %s:%d  %s', severity, vim.fn.fnamemodify(path, ':~:.'), d.lnum + 1, d.message),
        data = { severity = d.severity, bufnr = d.bufnr },
      }
    end

    table.sort(items, function(a, b)
      if a.data.severity ~= b.data.severity then return a.data.severity < b.data.severity end
      if a.path ~= b.path then return (a.path or '') < (b.path or '') end
      return a.line < b.line
    end)

    if query ~= '' then items = require('sources').filter(items, query) end

    vim.schedule(function()
      emit(items)
      done()
    end)

    return function() end
  end,
}

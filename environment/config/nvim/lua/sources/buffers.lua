return {
  name = 'buffers',
  description = 'Open (listed) buffers, most recently used first, with unsaved ones marked.',
  collect = function(query, _, emit, done)
    local items = {}

    for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
      local label = info.name ~= '' and vim.fn.fnamemodify(info.name, ':~:.') or ('[No Name] ' .. info.bufnr)

      items[#items + 1] = {
        kind = 'buffer',
        path = info.name ~= '' and info.name or nil,
        line = info.lnum,
        text = info.changed == 1 and 'unsaved changes' or nil,
        label = label .. (info.changed == 1 and ' [+]' or ''),
        data = { bufnr = info.bufnr, lastused = info.lastused },
      }
    end

    table.sort(items, function(a, b)
      return a.data.lastused > b.data.lastused
    end)

    if query ~= '' then items = require('sources').filter(items, query) end

    vim.schedule(function()
      emit(items)
      done()
    end)

    return function() end
  end,
}

local fs = require('core.fs')
local Timer = require('core.Timer')
local buffers = require('core.buffers')

return {
  name = 'buffers',
  description = 'Open (listed) buffers, most recently used first, with unsaved ones marked.',
  collect = function(query, _, emit, done)
    local items = {}

    for _, info in ipairs(buffers.listed()) do
      local label = info.name ~= '' and fs.display(info.name) or ('[No Name] ' .. info.bufnr)

      items[#items + 1] = {
        kind = 'buffer',
        path = info.name ~= '' and info.name or nil,
        line = info.line,
        text = info.changed and 'unsaved changes' or nil,
        label = label .. (info.changed and ' [+]' or ''),
        data = { bufnr = info.bufnr, lastused = info.lastused },
      }
    end

    table.sort(items, function(a, b)
      return a.data.lastused > b.data.lastused
    end)

    if query ~= '' then items = require('sources').filter(items, query) end

    Timer.schedule(function()
      emit(items)
      done()
    end)

    return function() end
  end,
}

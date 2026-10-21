local dataclass = require('core.dataclass')

local MarkSpec = dataclass.define('MarkSpec', {
  row = { type = 'number', required = true },
  col = { type = 'number', required = true },
  opts = { type = 'table', required = true },
})

MarkSpec.PRIORITY = 300

function MarkSpec.add(out, row, col, opts, priority)
  opts.priority = opts.priority or priority or MarkSpec.PRIORITY
  out[#out + 1] = MarkSpec({ row = row, col = col, opts = opts })
end

function MarkSpec.apply(buffer, namespace, marks)
  for _, mark in ipairs(marks) do
    buffer:set_extmark(namespace, mark.row, mark.col, mark.opts)
  end
end

return MarkSpec

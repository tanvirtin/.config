local help = {}

help.HEADER = { '| Key | Does |', '| --- | --- |' }

local function keys_of(lhs)
  return type(lhs) == 'table' and table.concat(lhs, ' ') or lhs
end

local function escape(text)
  return (text:gsub('|', '\\|'))
end

function help.rows(bindings)
  local rows = {}

  for _, binding in ipairs(bindings) do
    local lhs, desc = keys_of(binding[1]), binding[3]

    if lhs and desc then rows[#rows + 1] = { lhs = lhs, desc = desc } end
  end

  table.sort(rows, function(a, b)
    return a.lhs < b.lhs
  end)

  return rows
end

function help.markdown(bindings)
  local lines = vim.list_extend({}, help.HEADER)

  for _, row in ipairs(help.rows(bindings)) do
    lines[#lines + 1] = string.format('| `%s` | %s |', escape(row.lhs), escape(row.desc))
  end

  return table.concat(lines, '\n')
end

return help

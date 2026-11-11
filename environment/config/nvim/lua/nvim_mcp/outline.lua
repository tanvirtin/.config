local compact = require('compact')
local treesitter = require('core.treesitter')

local outline = {}

local WIDTH = 100

local KINDS = {
  ['function'] = true,
  method = true,
  class = true,
  struct = true,
  enum = true,
  interface = true,
  trait = true,
  impl = true,
  module = true,
  mod = true,
  namespace = true,
  type = true,
  macro = true,
}

local FORMS = {
  declaration = true,
  definition = true,
  item = true,
  specifier = true,
  spec = true,
}

local WHOLE = { method = true, class = true, module = true, section = true }

local function defines(kind)
  if WHOLE[kind] then return true end

  local words = vim.split(kind, '_', { plain = true })

  if not FORMS[words[#words]] then return false end

  for i = 1, #words - 1 do
    if KINDS[words[i]] then return true end
  end

  return false
end

local function span(node)
  local first, _, last, last_col = node:range()

  if last_col == 0 and last > first then last = last - 1 end

  return first + 1, last + 1
end

local function name_of(node, source)
  local field = node:field('name')[1]

  return field and compact.raw(treesitter.node_text(field, source)) or nil
end

local function walk(node, depth, source, lines, out)
  for child in node:iter_children() do
    local inner = depth

    if child:named() and defines(child:type()) then
      local first, last = span(child)
      local previous = out[#out]

      if last > first and not (previous and previous.first == first) then
        out[#out + 1] = {
          first = first,
          last = last,
          depth = depth,
          name = name_of(child, source),
          label = compact.line(lines[first] or '', WIDTH),
        }
        inner = depth + 1
      end
    end

    walk(child, inner, source, lines, out)
  end

  return out
end

function outline.of(root, source, lines)
  return walk(root, 0, source, lines, {})
end

local function named(entry, symbol)
  return entry.name == symbol
end

local function member(entry, symbol)
  local name = entry.name

  return name ~= nil and (vim.endswith(name, '.' .. symbol) or vim.endswith(name, ':' .. symbol))
end

local function mentions(entry, symbol)
  return entry.label:find(symbol, 1, true) ~= nil
end

function outline.find(entries, symbol)
  for _, matches in ipairs({ named, member, mentions }) do
    local found = vim.tbl_filter(function(entry)
      return matches(entry, symbol)
    end, entries)

    if #found > 0 then return found end
  end

  return {}
end

function outline.format(entries)
  if #entries == 0 then return 'no definitions' end

  local out = {}

  for i, entry in ipairs(entries) do
    out[i] = string.format('%s%d-%d %s', string.rep('  ', entry.depth), entry.first, entry.last, entry.label)
  end

  return table.concat(out, '\n')
end

return outline

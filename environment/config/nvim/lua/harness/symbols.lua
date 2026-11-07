local fs = require('core.fs')
local treesitter = require('core.treesitter')

local symbols = {}

symbols.KINDS = { 'function', 'method', 'class', 'struct', 'impl', 'interface', 'trait', 'enum', 'module', 'type' }

local function is_symbol(node)
  local kind = node:type()

  if kind:find('call', 1, true) then return false end

  for _, word in ipairs(symbols.KINDS) do
    if kind:find(word, 1, true) then return node:field('name')[1] ~= nil end
  end

  return false
end

local function normalize(name)
  return (name:gsub('[:#]', '.'))
end

local function language(path)
  local filetype = fs.detect_filetype(path)
  local lang = filetype and treesitter.language_of(filetype)

  if not lang then return nil end

  local ok, loaded = pcall(treesitter.add_language, lang)

  if not ok or loaded == false or loaded == nil then return nil end

  return lang
end

function symbols.parse(lines, path)
  local lang = language(path)

  if not lang then return {} end

  local text = table.concat(lines, '\n')
  local ok, parser = pcall(treesitter.string_parser, text, lang)

  if not ok or not parser then return {} end

  local found = {}

  local function walk(node, parent)
    for child in node:iter_children() do
      local owner = parent

      if child:named() and is_symbol(child) then
        local name = treesitter.node_text(child:field('name')[1], text)
        local start_row, _, end_row, end_col = child:range()

        if end_col == 0 and end_row > start_row then end_row = end_row - 1 end

        owner = { name = parent and (parent.name .. '.' .. name) or name, first = start_row + 1, last = end_row + 1 }
        found[#found + 1] = owner
      end

      walk(child, owner)
    end
  end

  walk(parser:parse()[1]:root(), nil)

  return found
end

function symbols.find(list, wanted)
  local target = normalize(wanted)
  local matches = {}

  for _, symbol in ipairs(list) do
    local name = normalize(symbol.name)

    if name == target then return symbol end
    if name:sub(-#target - 1) == '.' .. target then matches[#matches + 1] = symbol end
  end

  if #matches == 1 then return matches[1] end

  if #matches > 1 then
    local names = vim.tbl_map(function(symbol)
      return symbol.name
    end, matches)

    return nil, string.format('%s is ambiguous: %s', wanted, table.concat(names, ', '))
  end

  return nil, 'no symbol ' .. wanted
end

function symbols.enclosing(list, first, last)
  local best

  for _, symbol in ipairs(list) do
    if
      symbol.first <= first
      and symbol.last >= last
      and (not best or symbol.last - symbol.first < best.last - best.first)
    then
      best = symbol
    end
  end

  return best
end

return symbols

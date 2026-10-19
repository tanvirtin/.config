local lazy = require('core.lazy')

local Object = lazy('core.Object')

local SyntaxAnnotator = Object:extend()

function SyntaxAnnotator:constructor()
  return {
    _cache = {},
    _cache_max = 50,
    _cache_order = {},
  }
end

function SyntaxAnnotator:_cache_key(lines, filetype)
  local n = #lines
  if n == 0 then return nil end
  local hash = 5381
  for i = 1, n do
    local line = lines[i]
    for j = 1, #line do
      hash = ((hash * 33) + string.byte(line, j)) % 0x100000000
    end
    hash = ((hash * 33) + 10) % 0x100000000
  end
  return string.format('%s:%d:%u', filetype or '', n, hash)
end

function SyntaxAnnotator:_cache_put(key, value)
  if not self._cache[key] then self._cache_order[#self._cache_order + 1] = key end
  self._cache[key] = value
  while #self._cache_order > self._cache_max do
    local oldest = table.remove(self._cache_order, 1)
    self._cache[oldest] = nil
  end
end

function SyntaxAnnotator:clear_cache()
  self._cache = {}
  self._cache_order = {}
end

function SyntaxAnnotator:dispose()
  self:clear_cache()
end

function SyntaxAnnotator:_parse_highlights(source, filetype)
  local highlights = {}
  local lang = vim.treesitter.language.get_lang(filetype) or filetype

  if not pcall(vim.treesitter.language.add, lang) then return highlights end

  local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok or not parser then return highlights end

  local query_ok, query = pcall(vim.treesitter.query.get, lang, 'highlights')
  if not query_ok or not query then return highlights end

  local tree = parser:parse()[1]
  if not tree then return highlights end

  for id, node in query:iter_captures(tree:root(), source, 0, -1) do
    local name = query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()

    for row = start_row, end_row do
      highlights[#highlights + 1] = {
        row = row,
        col_start = (row == start_row) and start_col or 0,
        col_end = (row == end_row) and end_col or -1,
        hl_group = '@' .. name,
      }
    end
  end

  return highlights
end

function SyntaxAnnotator:annotate(lines, filetype)
  if not lines or #lines == 0 then return {} end

  if not filetype or filetype == '' or filetype == 'text' then return {} end

  local key = self:_cache_key(lines, filetype)
  if key and self._cache[key] then return self._cache[key] end

  local highlights = self:_parse_highlights(table.concat(lines, '\n'), filetype)

  if key then self:_cache_put(key, highlights) end

  return highlights
end

return SyntaxAnnotator

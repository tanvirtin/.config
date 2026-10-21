local Buffer = require('core.Buffer')
local MarkSpec = require('ui.MarkSpec')
local Object = require('core.Object')
local nodes = require('ui.markdown.nodes')
require('ui.hl')

local Renderer = Object:extend()

Renderer.NAMESPACE = Buffer.namespace('ui.markdown')

Renderer.INLINE = require('core.dataclass').enum({ 'link', 'code' })

Renderer.HEADING_ICONS = nodes.HEADING_ICONS
Renderer.BULLETS = nodes.BULLETS
Renderer.CALLOUTS = nodes.CALLOUTS
Renderer.RULE_WIDTH = nodes.RULE_WIDTH
Renderer.NODES = nodes.NODES

Renderer.HIGHLIGHT_PRIORITY = 100
Renderer.LINK_PRIORITY = 190

local QUERY = vim.treesitter.query.parse(
  'markdown',
  [[
  (atx_heading) @heading
  (fenced_code_block) @code
  [(list_marker_minus) (list_marker_plus) (list_marker_star)] @bullet
  (task_list_marker_checked) @checked
  (task_list_marker_unchecked) @unchecked
  (block_quote) @quote
  (thematic_break) @rule
  (pipe_table) @table
]]
)

local INLINE_QUERY = vim.treesitter.query.parse(
  'markdown_inline',
  [[
  (inline_link (link_destination) @link)
  (code_span) @code
]]
)

function Renderer:constructor(bufnr, opts)
  opts = opts or {}

  return {
    bufnr = bufnr,
    buffer = Buffer(bufnr),
    hidden_labels = opts.hidden_labels or {},
    resolve = opts.resolve,
  }
end

local function inline_text(text, kind)
  if kind == Renderer.INLINE.code then return (text:gsub('^`+%s?', ''):gsub('%s?`+$', '')) end

  return text
end

local queries = {}

function Renderer.highlights(lang)
  if queries[lang] == nil then
    local ok, query = pcall(function()
      local sources = {}

      for _, file in ipairs(vim.treesitter.query.get_files(lang, 'highlights')) do
        sources[#sources + 1] = table.concat(vim.fn.readfile(file), '\n')
      end

      return #sources > 0 and vim.treesitter.query.parse(lang, table.concat(sources, '\n')) or false
    end)

    queries[lang] = ok and query or false
  end

  return queries[lang] or nil
end

local function capture_option(metadata, id, key)
  return metadata[key] or (metadata[id] and metadata[id][key])
end

local function highlight(out, parser, src)
  parser:for_each_tree(function(tree, ltree)
    local lang = ltree:lang()
    local query = Renderer.highlights(lang)

    if not query then return end

    for id, node, metadata in query:iter_captures(tree:root(), src.text) do
      local name = query.captures[id]

      if name:sub(1, 1) ~= '_' and name ~= 'spell' and name ~= 'nospell' then
        local range = vim.treesitter.get_range(node, src.text, metadata[id])
        local priority = tonumber(capture_option(metadata, id, 'priority')) or 0
        local opts = {
          end_row = range[4] + src.offset,
          end_col = range[5],
          priority = Renderer.HIGHLIGHT_PRIORITY + priority,
          conceal = capture_option(metadata, id, 'conceal'),
        }

        if name ~= 'conceal' then opts.hl_group = '@' .. name .. '.' .. lang end
        if capture_option(metadata, id, 'conceal_lines') then opts.conceal_lines = '' end

        nodes.mark(out, range[1] + src.offset, range[2], opts)
      end
    end
  end)
end

function Renderer:_inline(out, parser, src)
  if not self.resolve then return end

  local child = parser:children().markdown_inline

  if not child then return end

  for _, tree in pairs(child:trees()) do
    for id, node in INLINE_QUERY:iter_captures(tree:root(), src.text) do
      local kind = INLINE_QUERY.captures[id]
      local decoration = self.resolve(kind, inline_text(src:node_text(node), kind))

      if decoration then
        local row, col, end_row, end_col = src:range(kind == Renderer.INLINE.link and node:parent() or node)

        nodes.mark(out, row, col, { virt_text = { decoration.icon }, virt_text_pos = 'inline' })
        nodes.mark(out, row, col, {
          end_row = end_row,
          end_col = end_col,
          hl_group = 'UiMarkdownLink',
          priority = Renderer.LINK_PRIORITY,
        })
      end
    end
  end
end

function Renderer:annotate(lines, offset)
  local out = {}
  local src = nodes.source(lines, offset or 0)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src.text, 'markdown')

  if not ok or not parser then return out end

  local tree = parser:parse(true)[1]

  if not tree then return out end

  for id, node in QUERY:iter_captures(tree:root(), src.text) do
    nodes.NODES[QUERY.captures[id]](out, node, src, self)
  end

  highlight(out, parser, src)
  self:_inline(out, parser, src)

  return out
end

function Renderer:inline_at(row, col)
  local line = self.buffer:get_lines(row, row + 1)[1]

  if not line or line == '' then return nil end

  local parser = vim.treesitter.get_string_parser(line, 'markdown')

  parser:parse(true)

  local child = parser:children().markdown_inline

  if not child then return nil end

  for _, tree in pairs(child:trees()) do
    local node = tree:root():named_descendant_for_range(0, col, 0, col)

    while node do
      local type = node:type()

      if type == 'inline_link' then
        for part in node:iter_children() do
          if part:type() == 'link_destination' then
            return Renderer.INLINE.link, inline_text(vim.treesitter.get_node_text(part, line), Renderer.INLINE.link)
          end
        end
      elseif type == 'code_span' then
        return Renderer.INLINE.code, inline_text(vim.treesitter.get_node_text(node, line), Renderer.INLINE.code)
      end

      node = node:parent()
    end
  end
end

function Renderer:clear(from_row, to_row)
  self.buffer:clear_namespace(Renderer.NAMESPACE, from_row, to_row or -1)
end

function Renderer:apply(marks)
  MarkSpec.apply(self.buffer, Renderer.NAMESPACE, marks)
end

function Renderer:render(from_row, to_row)
  if not self.buffer:is_valid() then return end

  to_row = to_row or self.buffer:get_line_count()
  self:clear(from_row, to_row)
  self:apply(self:annotate(self.buffer:get_lines(from_row, to_row), from_row))
end

return Renderer

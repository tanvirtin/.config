local Object = require('core.Object')
require('ui.hl')

local Renderer = Object:extend()

Renderer.NAMESPACE = vim.api.nvim_create_namespace('ui.markdown')

Renderer.INLINE = require('core.dataclass').enum({ 'link', 'code' })

Renderer.HEADING_ICONS = { '󰉫 ', '󰉬 ', '󰉭 ', '󰉮 ', '󰉯 ', '󰉰 ' }

Renderer.BULLETS = { '•', '◦', '▪', '▫' }

Renderer.CALLOUTS = {
  note = { icon = '󰋽 ', hl = 'UiInfo' },
  info = { icon = '󰋽 ', hl = 'UiInfo' },
  tip = { icon = '󰌶 ', hl = 'UiHint' },
  important = { icon = '󰅾 ', hl = 'UiHint' },
  warning = { icon = '󰀪 ', hl = 'UiWarn' },
  caution = { icon = '󰳦 ', hl = 'UiError' },
  thought = { icon = '󰟶 ', hl = 'UiMuted' },
}

Renderer.RULE_WIDTH = 400

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

  return { bufnr = bufnr, hidden_labels = opts.hidden_labels or {}, resolve = opts.resolve }
end

Renderer.HIGHLIGHT_PRIORITY = 100

function Renderer:_mark(row, col, opts)
  opts.priority = opts.priority or 200
  opts.strict = false
  pcall(vim.api.nvim_buf_set_extmark, self.bufnr, Renderer.NAMESPACE, row, col, opts)
end

local function depth(node, type)
  local count = 0
  local parent = node:parent()

  while parent do
    if parent:type() == type then count = count + 1 end
    parent = parent:parent()
  end

  return count
end

local Source = {}
Source.__index = Source

local function source(lines, offset)
  return setmetatable({ lines = lines, offset = offset, text = table.concat(lines, '\n') .. '\n' }, Source)
end

function Source:line(row)
  return self.lines[row - self.offset + 1] or ''
end

function Source:range(node)
  local start_row, start_col, end_row, end_col = node:range()

  return start_row + self.offset, start_col, end_row + self.offset, end_col
end

function Source:start(node)
  local row, col = node:start()

  return row + self.offset, col
end

function Source:last_row(node)
  local _, _, end_row, end_col = self:range(node)

  return end_col == 0 and end_row - 1 or end_row
end

function Source:node_text(node)
  return vim.treesitter.get_node_text(node, self.text)
end

local NODES = {}

function NODES.heading(self, node, src)
  local row = src:start(node)
  local marker = node:child(0)
  local level = tonumber(marker:type():match('atx_h(%d)_marker')) or 1
  local _, _, _, marker_end = marker:range()
  local text = src:line(row)
  local hide = marker_end + (text:sub(marker_end + 1, marker_end + 1) == ' ' and 1 or 0)

  self:_mark(row, 0, { end_col = hide, conceal = '' })
  self:_mark(row, 0, {
    virt_text = { { Renderer.HEADING_ICONS[level], 'UiMarkdownHeading' .. level } },
    virt_text_pos = 'inline',
    line_hl_group = 'UiMarkdownHeading',
    hl_group = 'UiMarkdownHeading' .. level,
    end_row = row,
    end_col = #text,
  })
end

function NODES.code(self, node, src)
  local start_row = src:start(node)
  local language

  for child in node:iter_children() do
    if child:type() == 'info_string' then
      local lang = child:named_child(0)
      language = src:node_text(lang or child)
    end
  end

  local last = src:last_row(node)

  for row = start_row, last do
    self:_mark(row, 0, { line_hl_group = 'UiMarkdownCode', priority = 50 })
  end

  if language and not self.hidden_labels[language] and start_row + 1 <= last then
    self:_mark(start_row + 1, 0, { virt_text = { { language .. ' ', 'UiMuted' } }, virt_text_pos = 'right_align' })
  end
end

local function is_task(marker)
  local next = marker:next_named_sibling()
  local type = next and next:type() or ''

  return type == 'task_list_marker_checked' or type == 'task_list_marker_unchecked'
end

function NODES.bullet(self, node, src)
  local row, col, _, end_col = src:range(node)
  local bullets = Renderer.BULLETS

  if is_task(node) then return self:_mark(row, col, { end_col = end_col, conceal = '' }) end

  self:_mark(row, col, {
    end_col = col + 1,
    virt_text = { { bullets[(depth(node, 'list') - 1) % #bullets + 1], 'UiMarkdownBullet' } },
    virt_text_pos = 'overlay',
  })
end

local function checkbox(icon, hl)
  return function(self, node, src)
    local row, col, _, end_col = src:range(node)

    self:_mark(row, col, { end_col = end_col, conceal = '' })
    self:_mark(row, col, { virt_text = { { icon, hl } }, virt_text_pos = 'inline' })
  end
end

NODES.checked = checkbox('󰱒', 'UiMarkdownChecked')
NODES.unchecked = checkbox('󰄱', 'UiMarkdownUnchecked')

function NODES.quote(self, node, src)
  local start_row = src:start(node)
  local first = src:line(start_row)
  local name = first:match('^[%s>]*%[!(%a+)%]')
  local callout = name and Renderer.CALLOUTS[name:lower()]
  local bar_hl = callout and callout.hl or 'UiMarkdownQuote'

  for row = start_row, src:last_row(node) do
    local text = src:line(row)
    local markers = text:match('^[%s>]*')

    for col = 1, #markers do
      if markers:sub(col, col) == '>' then
        self:_mark(row, col - 1, { end_col = col, virt_text = { { '▎', bar_hl } }, virt_text_pos = 'overlay' })
      end
    end

    if callout and row == start_row then
      local title = text:sub(#markers + 1):gsub('^%[!%a+%]%s*', '')

      self:_mark(row, #markers, { end_col = #text, conceal = '' })
      self:_mark(row, #markers, {
        virt_text = {
          { callout.icon .. (title ~= '' and title or name:sub(1, 1):upper() .. name:sub(2):lower()), callout.hl },
        },
        virt_text_pos = 'inline',
      })
    end
  end
end

function NODES.rule(self, node, src)
  local row = src:start(node)

  self:_mark(row, 0, {
    virt_text = { { string.rep('─', Renderer.RULE_WIDTH), 'UiMarkdownRule' } },
    virt_text_pos = 'overlay',
    virt_text_win_col = 0,
  })
end

Renderer.NODES = NODES

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

function Renderer:_highlight(parser, src)
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

        self:_mark(range[1] + src.offset, range[2], opts)
      end
    end
  end)
end

function Renderer:_inline(parser, src)
  if not self.resolve then return end

  local child = parser:children().markdown_inline

  if not child then return end

  for _, tree in pairs(child:trees()) do
    for id, node in INLINE_QUERY:iter_captures(tree:root(), src.text) do
      local kind = INLINE_QUERY.captures[id]
      local decoration = self.resolve(kind, inline_text(src:node_text(node), kind))

      if decoration then
        local row, col, end_row, end_col = src:range(kind == Renderer.INLINE.link and node:parent() or node)

        self:_mark(row, col, { virt_text = { decoration.icon }, virt_text_pos = 'inline' })
        self:_mark(row, col, { end_row = end_row, end_col = end_col, hl_group = 'UiMarkdownLink', priority = 190 })
      end
    end
  end
end

function Renderer:inline_at(row, col)
  local line = vim.api.nvim_buf_get_lines(self.bufnr, row, row + 1, false)[1]

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
  vim.api.nvim_buf_clear_namespace(self.bufnr, Renderer.NAMESPACE, from_row, to_row or -1)
end

function Renderer:render(from_row, to_row)
  if not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  to_row = to_row or vim.api.nvim_buf_line_count(self.bufnr)
  self:clear(from_row, to_row)

  local src = source(vim.api.nvim_buf_get_lines(self.bufnr, from_row, to_row, false), from_row)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src.text, 'markdown')

  if not ok or not parser then return end

  local tree = parser:parse(true)[1]

  if not tree then return end

  for id, node in QUERY:iter_captures(tree:root(), src.text) do
    NODES[QUERY.captures[id]](self, node, src)
  end

  self:_highlight(parser, src)
  self:_inline(parser, src)
end

return Renderer

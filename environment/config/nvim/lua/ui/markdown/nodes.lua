local MarkSpec = require('ui.MarkSpec')

local nodes = {}

nodes.PRIORITY = 200

nodes.HEADING_ICONS = { '󰉫 ', '󰉬 ', '󰉭 ', '󰉮 ', '󰉯 ', '󰉰 ' }

nodes.BULLETS = { '•', '◦', '▪', '▫' }

nodes.CALLOUTS = {
  note = { icon = '󰋽 ', hl = 'UiInfo' },
  info = { icon = '󰋽 ', hl = 'UiInfo' },
  tip = { icon = '󰌶 ', hl = 'UiHint' },
  important = { icon = '󰅾 ', hl = 'UiHint' },
  warning = { icon = '󰀪 ', hl = 'UiWarn' },
  caution = { icon = '󰳦 ', hl = 'UiError' },
  thought = { icon = '󰟶 ', hl = 'UiMuted' },
}

nodes.RULE_WIDTH = 400

function nodes.mark(out, row, col, opts)
  opts.strict = false
  MarkSpec.add(out, row, col, opts, nodes.PRIORITY)
end

local mark = nodes.mark

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

function nodes.source(lines, offset)
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

function NODES.heading(out, node, src)
  local row = src:start(node)
  local marker = node:child(0)
  local level = tonumber(marker:type():match('atx_h(%d)_marker')) or 1
  local _, _, _, marker_end = marker:range()
  local text = src:line(row)
  local hide = marker_end + (text:sub(marker_end + 1, marker_end + 1) == ' ' and 1 or 0)

  mark(out, row, 0, { end_col = hide, conceal = '' })
  mark(out, row, 0, {
    virt_text = { { nodes.HEADING_ICONS[level], 'UiMarkdownHeading' .. level } },
    virt_text_pos = 'inline',
    line_hl_group = 'UiMarkdownHeading',
    hl_group = 'UiMarkdownHeading' .. level,
    end_row = row,
    end_col = #text,
  })
end

function NODES.code(out, node, src, opts)
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
    mark(out, row, 0, { line_hl_group = 'UiMarkdownCode', priority = 50 })
  end

  if language and not opts.hidden_labels[language] and start_row + 1 <= last then
    mark(out, start_row + 1, 0, { virt_text = { { language .. ' ', 'UiMuted' } }, virt_text_pos = 'right_align' })
  end
end

local function is_task(marker)
  local next = marker:next_named_sibling()
  local type = next and next:type() or ''

  return type == 'task_list_marker_checked' or type == 'task_list_marker_unchecked'
end

function NODES.bullet(out, node, src)
  local row, col, _, end_col = src:range(node)
  local bullets = nodes.BULLETS

  if is_task(node) then return mark(out, row, col, { end_col = end_col, conceal = '' }) end

  mark(out, row, col, {
    end_col = col + 1,
    virt_text = { { bullets[(depth(node, 'list') - 1) % #bullets + 1], 'UiMarkdownBullet' } },
    virt_text_pos = 'overlay',
  })
end

local function checkbox(icon, hl)
  return function(out, node, src)
    local row, col, _, end_col = src:range(node)

    mark(out, row, col, { end_col = end_col, conceal = '' })
    mark(out, row, col, { virt_text = { { icon, hl } }, virt_text_pos = 'inline' })
  end
end

NODES.checked = checkbox('󰱒', 'UiMarkdownChecked')
NODES.unchecked = checkbox('󰄱', 'UiMarkdownUnchecked')

function NODES.quote(out, node, src)
  local start_row = src:start(node)
  local first = src:line(start_row)
  local name = first:match('^[%s>]*%[!(%a+)%]')
  local callout = name and nodes.CALLOUTS[name:lower()]
  local bar_hl = callout and callout.hl or 'UiMarkdownQuote'

  for row = start_row, src:last_row(node) do
    local text = src:line(row)
    local markers = text:match('^[%s>]*')

    for col = 1, #markers do
      if markers:sub(col, col) == '>' then
        mark(out, row, col - 1, { end_col = col, virt_text = { { '▎', bar_hl } }, virt_text_pos = 'overlay' })
      end
    end

    if callout and row == start_row then
      local title = text:sub(#markers + 1):gsub('^%[!%a+%]%s*', '')

      mark(out, row, #markers, { end_col = #text, conceal = '' })
      mark(out, row, #markers, {
        virt_text = {
          { callout.icon .. (title ~= '' and title or name:sub(1, 1):upper() .. name:sub(2):lower()), callout.hl },
        },
        virt_text_pos = 'inline',
      })
    end
  end
end

function NODES.rule(out, node, src)
  local row = src:start(node)

  mark(out, row, 0, {
    virt_text = { { string.rep('─', nodes.RULE_WIDTH), 'UiMarkdownRule' } },
    virt_text_pos = 'overlay',
    virt_text_win_col = 0,
  })
end

nodes.NODES = NODES

return nodes

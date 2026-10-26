local hit_test = require('harness.ui.hit_test')

local function cell(block, row, col)
  local lines = block.lines

  if not lines or #lines == 0 then return nil end

  local start = block.start or 0
  local relative = row - start

  if relative < 0 or relative >= #lines then return nil end

  local text = table.concat(lines, '\n')
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, 'markdown')

  if not ok or not parser then return nil end

  local tree = parser:parse(true)[1]

  if not tree then return nil end

  local node = tree:root():named_descendant_for_range(relative, col, relative, col)

  while node and node:type() ~= 'pipe_table_cell' do
    node = node:parent()
  end

  if not node then return nil end

  return { text = vim.trim(vim.treesitter.get_node_text(node, text)), kind = 'cell' }
end

hit_test.bind('markdown', cell)

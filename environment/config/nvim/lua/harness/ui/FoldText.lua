local lazy = require('core.lazy')

local core_text = lazy('core.text')
local Object = require('core.Object')
local theme = lazy('harness.transcript.theme')
local Block = require('harness.transcript.Block')
local fold_summary = require('harness.transcript.fold_summary')

local FoldText = Object:extend()

FoldText.SUMMED = { tool = 'tool', message = 'reply' }

FoldText.MANY = { tool = 'tools', reply = 'replies' }

function FoldText:constructor(document)
  return { document = document }
end

function FoldText:_children_in(first, last)
  local counts = {}

  for _, block in ipairs(self.document.blocks) do
    if block.start >= first and block.start < last then
      if not block.depth then return nil end

      local noun = FoldText.SUMMED[block.kind]

      if noun then counts[noun] = (counts[noun] or 0) + 1 end
    end
  end

  local parts = {}

  for _, noun in ipairs({ 'tool', 'reply' }) do
    local n = counts[noun]

    if n then parts[#parts + 1] = core_text.plural(n, noun, FoldText.MANY[noun]) end
  end

  return #parts > 0 and table.concat(parts, ' · ') or nil
end

function FoldText:_rails(row, last)
  local document = self.document
  local block = document:block_at(row)
  local depth = block and (block.depth or 0) + (row > block.start and 1 or 0) or 0

  if depth == 0 then return '  ' end

  local tail = document:block_at(last)
  local closes = tail and tail.last_child and last >= tail.start + #tail.lines and row == block.start

  return string.rep(theme.GUTTER, depth - 1) .. (closes and theme.BRANCH_END or theme.GUTTER)
end

function FoldText:_line_summary(first, last)
  local block = self.document:block_at(first - 1)

  return fold_summary.text(
    core_text.plural(last - first + 1, 'more line'),
    vim.list_slice(self.document.lines, first, last),
    block ~= nil and block.status == Block.STATUS.failed,
    block ~= nil and block.category == Block.CATEGORY.execute
  )
end

function FoldText:text(first, last)
  local children = self:_children_in(first - 1, last)
  local text = '⋯ ' .. (children or self:_line_summary(first, last))

  return { { self:_rails(first - 1, last - 1), 'UiMuted' }, { text, 'UiMuted' } }
end

return FoldText

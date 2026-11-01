local lazy = require('core.lazy')

local fences = lazy('core.fences')
local Window = lazy('core.Window')
local Buffer = lazy('core.Buffer')
local settings = lazy('harness.settings')
local Block = require('harness.transcript.Block')

local hints = {}

hints.NAMESPACE = Buffer.namespace('harness.hints')

hints.SEPARATOR = ' · '

hints.EDITING = {
  [Block.CATEGORY.edit] = true,
  [Block.CATEGORY.delete] = true,
  [Block.CATEGORY.move] = true,
}

local function join(keys, pairs_)
  local parts = {}

  for _, entry in ipairs(pairs_) do
    local lhs = keys[entry[1]]

    if lhs then parts[#parts + 1] = lhs .. ' ' .. entry[2] end
  end

  return #parts > 0 and table.concat(parts, hints.SEPARATOR) or nil
end

function hints.text(block, keys, in_code)
  if not block then return nil end

  if block.kind == Block.KIND.diff then
    return join(keys, { { 'diff', 'diff' }, { 'open', 'open' }, { 'revert', 'revert' } })
  end

  if block.kind == Block.KIND.tool then
    if hints.EDITING[block.category] then
      return join(keys, { { 'diff', 'diff' }, { 'open', 'open' }, { 'git_diff', 'git diff' }, { 'revert', 'revert' } })
    end

    if block.category == Block.CATEGORY.read then
      return join(keys, { { 'open', 'open' }, { 'git_diff', 'git diff' } })
    end

    return nil
  end

  if block.kind == Block.KIND.message then
    if in_code then return join(keys, { { 'apply', 'apply' }, { 'insert', 'insert' }, { 'yank', 'yank' } }) end

    return join(keys, { { 'yank', 'yank' }, { 'fork', 'fork' } })
  end

  if block.kind == Block.KIND.prompt then return join(keys, { { 'fork', 'fork' } }) end

  return nil
end

function hints.in_code(block, row)
  if block.kind ~= Block.KIND.message then return false end

  return fences.fenced_at(block.lines, row - block.start + 1) ~= nil
end

function hints.clear(view)
  view.buffer:clear_namespace(hints.NAMESPACE, 0, -1)
end

function hints.show(view)
  hints.clear(view)

  if not settings.transcript:get('hints') then return false end

  local window = Window.get_current()

  if window:get_buffer().bufnr ~= view.bufnr then return false end

  local row = window:get_cursor()[1] - 1
  local block = view.document:block_at(row)
  local text = block and hints.text(block, settings.keymaps:get('transcript'), hints.in_code(block, row))

  if not text then return false end

  view.buffer:set_extmark(hints.NAMESPACE, block.start, 0, {
    virt_text = { { '  ' .. text, 'UiMuted' } },
    virt_text_pos = 'eol',
    hl_mode = 'combine',
  })

  return true
end

return hints

local lazy = require('core.lazy')

local Window = lazy('core.Window')
local Block = require('harness.transcript.Block')

local objects = {}

objects.KIND = { turn = 'turn', message = 'message', tool = 'tool' }

local function last_row(block)
  return block.start + #block.lines - 1
end

local function owner(blocks, row)
  for i, block in ipairs(blocks) do
    if block.start and row >= block.start and row <= last_row(block) then return i end
  end
end

local function turn_range(blocks, row, around)
  local from = owner(blocks, row)

  if not from then return nil end

  while from >= 1 and blocks[from].kind ~= Block.KIND.prompt do
    from = from - 1
  end

  if from < 1 then return nil end

  local to = #blocks

  for i = from + 1, #blocks do
    if blocks[i].kind == Block.KIND.prompt then
      to = i - 1
      break
    end
  end

  local top = around and blocks[from].start or last_row(blocks[from]) + 1
  local bottom = last_row(blocks[to])

  if bottom < top then return nil end

  return top, bottom
end

local function block_range(blocks, row, around, kinds)
  local index = owner(blocks, row)
  local block = index and blocks[index]

  if not block or not kinds[block.kind] then return nil end

  local top = around and block.start or math.min(block.start + 1, last_row(block))

  return top, last_row(block)
end

local KINDS = {
  message = { [Block.KIND.message] = true, [Block.KIND.thought] = true },
  tool = { [Block.KIND.tool] = true, [Block.KIND.diff] = true },
}

function objects.range(blocks, row, kind, around)
  if kind == objects.KIND.turn then return turn_range(blocks, row, around) end

  return block_range(blocks, row, around, KINDS[kind])
end

function objects.select(view, kind, around)
  local window = Window.get_current()
  local top, bottom = objects.range(view.document.blocks, window:get_cursor()[1] - 1, kind, around)

  if not top then return false, 'no ' .. kind .. ' here' end

  window:select_lines(top + 1, bottom + 1)

  return true
end

return objects

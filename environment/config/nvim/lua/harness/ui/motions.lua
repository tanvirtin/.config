local lazy = require('core.lazy')

local Window = lazy('core.Window')
local keymap = lazy('core.keymap')
local asks = lazy('harness.ui.asks')
local Block = require('harness.transcript.Block')

local motions = {}

motions.KIND = { turn = 'turn', tool = 'tool', edit = 'edit', waiting = 'waiting', failed = 'failed' }

motions.EMPTY = {
  turn = 'turn',
  tool = 'tool call',
  edit = 'edit',
  waiting = 'request waiting for you',
  failed = 'failed tool call',
}

local EDITING = {
  [Block.CATEGORY.edit] = true,
  [Block.CATEGORY.delete] = true,
  [Block.CATEGORY.move] = true,
}

local function waiting_ids(requests)
  local ids = {}

  for _, request in ipairs(requests or {}) do
    if request.id then ids[request.id] = true end
  end

  return ids
end

local MATCH = {
  turn = function(block)
    return block.kind == Block.KIND.prompt
  end,
  tool = function(block)
    return block.kind == Block.KIND.tool
  end,
  edit = function(block)
    return block.kind == Block.KIND.diff or (block.kind == Block.KIND.tool and EDITING[block.category] == true)
  end,
  failed = function(block)
    return block.kind == Block.KIND.tool and block.status == Block.STATUS.failed
  end,
}

function motions.rows(blocks, kind, context)
  local rows = {}
  local ids = kind == motions.KIND.waiting and waiting_ids(context and context.waiting)
  local match = MATCH[kind]

  for _, block in ipairs(blocks) do
    if block.start then
      local hit = ids and block.kind == Block.KIND.tool and block.id and ids[block.id] or match and match(block)

      if hit then rows[#rows + 1] = block.start end
    end
  end

  if ids and context and context.last and #(context.asks or {}) > 0 then
    if rows[#rows] ~= context.last then rows[#rows + 1] = context.last end
  end

  return rows
end

function motions.pick(rows, row, direction, count)
  local seen = 0
  count = count or 1

  if direction > 0 then
    for _, candidate in ipairs(rows) do
      if candidate > row then
        seen = seen + 1
        if seen == count then return candidate end
      end
    end

    return nil
  end

  for i = #rows, 1, -1 do
    if rows[i] < row then
      seen = seen + 1
      if seen == count then return rows[i] end
    end
  end
end

function motions.context(view)
  local session = view.session

  return {
    waiting = session:waiting(),
    asks = asks.asks_of(session),
    last = view.buffer:get_line_count() - 1,
  }
end

function motions.jump(view, kind, direction, count)
  local window = Window.get_current()
  local row = window:get_cursor()[1] - 1
  local rows = motions.rows(view.document.blocks, kind, motions.context(view))
  local target = motions.pick(rows, row, direction, count or keymap.count())

  if not target then
    return false, string.format('no %s %s', motions.EMPTY[kind], direction > 0 and 'below' or 'above')
  end

  window:jump_to({ target + 1, 0 })

  return true
end

return motions

local Block = require('harness.transcript.Block')
local Buffer = require('core.Buffer')
local Flashes = require('harness.ui.Flashes')

local eq = assert.are.same

describe('harness.ui.Flashes:', function()
  local buffer, flashes

  before_each(function()
    buffer = Buffer():create(false, true)
    buffer:set_lines({ 'a', 'b', 'c' })
    flashes = Flashes(buffer)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buffer.bufnr, { force = true })
  end)

  local function tool(fields)
    return vim.tbl_extend(
      'force',
      { kind = Block.KIND.tool, id = 't', start = 1, status = Block.STATUS.completed },
      fields
    )
  end

  local function marks()
    return vim.tbl_map(function(mark)
      return { mark[2], mark[4].line_hl_group }
    end, buffer:get_extmarks(Flashes.NAMESPACE, 0, -1, { details = true }))
  end

  it('flashes a tool that just finished, and leaves older ones and running ones alone', function()
    eq(true, flashes:scan({ tool({ finished = 1000 }) }, 1100))
    eq(false, Flashes(buffer):scan({ tool({ finished = 0 }) }, 5000))
    eq(false, Flashes(buffer):scan({ tool({}) }, 5000))
  end)

  it('flashes the rule of a turn that just ended, in the error tone when it did not end cleanly', function()
    flashes:scan({ { kind = Block.KIND.stop, start = 2, reason = 'end_turn', finished = 1000 } }, 1000)
    flashes:step(1000)
    eq({ { 2, 'UiFlashAccent1' } }, marks())

    local failed = Flashes(buffer)

    failed:scan({ { kind = Block.KIND.stop, start = 0, reason = 'max_tokens', finished = 1000 } }, 1000)
    eq('Error', failed.active['stop:0'].tone)
  end)

  it('fades the head row from the accent toward the resting surface, then removes its mark', function()
    flashes:scan({ tool({ finished = 1000 }) }, 1000)

    eq(true, flashes:step(1000))
    eq({ { 1, 'UiFlashAccent1' } }, marks())

    flashes:step(1200)

    local late = marks()[1][2]

    assert.is_true(tonumber(late:match('%d+$')) > 1)
    eq(1, #marks())

    eq(false, flashes:step(1300))
    eq({}, marks())
  end)

  it('flashes a failed tool in the error tone', function()
    flashes:scan({ tool({ finished = 1000, status = Block.STATUS.failed }) }, 1000)
    flashes:step(1000)

    eq('UiFlashError1', marks()[1][2])
  end)

  it('follows the block when the document moves it', function()
    flashes:scan({ tool({ finished = 1000 }) }, 1000)
    flashes:step(1000)
    flashes:scan({ tool({ finished = 1000, start = 2 }) }, 1050)
    flashes:step(1050)

    eq(2, marks()[1][1])
    eq(1, #marks())
  end)

  it('only looks at the newest blocks, so a long transcript costs a render no more', function()
    local list = { tool({ id = 'old', finished = 1000 }) }

    for index = 1, Flashes.LOOKBACK do
      list[#list + 1] = { kind = Block.KIND.message, start = index + 1 }
    end

    eq(false, flashes:scan(list, 1000))
    eq(true, flashes:scan({ tool({ id = 'recent', finished = 1000 }) }, 1000))
  end)
end)

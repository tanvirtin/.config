local Buffer = require('core.Buffer')
local Flashes = require('harness.ui.Flashes')
local Block = require('harness.transcript.Block')

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

  local function cells()
    return buffer:get_extmarks(Flashes.GLITCH, 0, -1, { details = true })
  end

  local function rows()
    local seen, out = {}, {}

    for _, mark in ipairs(cells()) do
      if not seen[mark[2]] then
        seen[mark[2]] = true
        out[#out + 1] = mark[2]
      end
    end

    return out
  end

  it('flashes a tool that just finished, and leaves older ones and running ones alone', function()
    eq(true, flashes:scan({ tool({ finished = 1000 }) }, 1100))
    eq(false, Flashes(buffer):scan({ tool({ finished = 0 }) }, 5000))
    eq(false, Flashes(buffer):scan({ tool({}) }, 5000))
  end)

  it(
    'breaks the summary of a turn that just ended into static, in the error tone when it did not end cleanly',
    function()
      buffer:set_lines({ 'a', 'b', 'done in 12s' })
      flashes:scan({ { kind = Block.KIND.stop, start = 2, reason = 'end_turn', finished = 1000 } }, 1000)
      flashes:step(1000)

      eq({ 2 }, rows())
      eq('UiAccent', cells()[1][4].virt_text[1][2])

      local failed = Flashes(buffer)

      failed:scan({ { kind = Block.KIND.stop, start = 0, reason = 'max_tokens', finished = 1000 } }, 1000)
      eq('Error', failed.active['stop:0'].tone)
    end
  )

  it('covers a finished row in static that clears, heavier and red when it failed, and then leaves it clean', function()
    buffer:set_lines({ 'a', '-> Bash make test passed with flying colours', 'c' })

    local ms = require('harness.settings').transcript:get('flash_ms')

    flashes:scan({ tool({ start = 1, finished = 1000 }) }, 1000)
    eq(true, flashes:step(1000))

    local early = #cells()

    assert.is_true(early > 0)
    eq('overlay', cells()[1][4].virt_text_pos)
    assert.is_true(cells()[1][3] >= 3)

    flashes:step(1000 + ms * 0.7)
    assert.is_true(#cells() < early)

    eq(false, flashes:step(1000 + ms))
    eq({}, cells())

    local failed = Flashes(buffer)

    failed:scan({ tool({ id = 'f', start = 1, finished = 1000, status = Block.STATUS.failed }) }, 1000)
    failed:step(1000)

    eq('UiError', cells()[1][4].virt_text[1][2])
  end)

  it('follows the block when the document moves it', function()
    buffer:set_lines({ 'a', '-> Bash one', '-> Bash two' })
    flashes:scan({ tool({ finished = 1000 }) }, 1000)
    flashes:step(1000)
    flashes:scan({ tool({ finished = 1000, start = 2 }) }, 1050)
    flashes:step(1050)

    eq({ 2 }, rows())
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

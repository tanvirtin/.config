local Tile = require('ui.pixel.Tile')
local Block = require('sn.transcript.model.Block')
local indicators = require('ui.pixel.indicators')
local Bursts = require('sn.transcript.effects.Bursts')

local eq = assert.are.same

local function tool(fields)
  return vim.tbl_extend('force', { kind = Block.KIND.tool, id = 't1', finished = 1000 }, fields)
end

describe('sn.transcript.effects.Bursts:', function()
  local original

  before_each(function()
    original = Tile.available
    Tile.available = function()
      return true
    end
  end)

  after_each(function()
    Tile.available = original
  end)

  local function view(blocks, calls)
    return {
      document = {
        blocks = blocks,
        redecorate = function(_, index)
          calls[#calls + 1] = index
        end,
      },
    }
  end

  it('picks up a tool that just finished, and ignores old, anonymous and non-tool blocks', function()
    local now = 1000 + 10

    eq(true, Bursts({ document = { blocks = {} } }):scan({ tool({}) }, now))
    eq(false, Bursts({ document = { blocks = {} } }):scan({ tool({ finished = 1 }) }, now))
    local anonymous = tool({})

    anonymous.id = nil
    eq(false, Bursts({ document = { blocks = {} } }):scan({ anonymous }, now))
    eq(
      false,
      Bursts({ document = { blocks = {} } }):scan({ { kind = Block.KIND.message, id = 't1', finished = 1000 } }, now)
    )
  end)

  it('does nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    eq(false, Bursts({ document = { blocks = {} } }):scan({ tool({}) }, 1010))
  end)

  it('keeps the burst alive until it has played out, then redecorates that block once', function()
    local blocks, calls = { tool({}) }, {}
    local bursts = Bursts(view(blocks, calls))

    eq(true, bursts:scan(blocks, 1010))
    eq(true, bursts:step(1000 + indicators.FINISH_MS - 1))
    eq({}, calls)

    eq(false, bursts:step(1000 + indicators.FINISH_MS))
    eq({ 1 }, calls)
  end)
end)

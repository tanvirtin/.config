local Tile = require('ui.pixel.Tile')
local graphics = require('core.graphics')
local rule = require('harness.transcript.rule')

local eq = assert.are.same

local GROUP = 'RuleSpecGroup'

local function cells(chunks)
  local total = 0

  for _, chunk in ipairs(chunks) do
    total = total + vim.fn.strdisplaywidth(chunk[1])
  end

  return total
end

local function alpha(upload, x, y)
  return string.byte(upload.bytes, (y * upload.width + x) * 4 + 4)
end

local function upload_of(uploads, cols)
  for _, upload in ipairs(uploads) do
    if upload.cols == cols then return upload end
  end
end

describe('harness.transcript.rule:', function()
  local original, uploads, deleted

  before_each(function()
    uploads, deleted = {}, {}
    original = { available = Tile.available, upload = graphics.upload, delete = graphics.delete }
    Tile.available = function()
      return true
    end
    graphics.upload = function(id, bytes, width, height, cols)
      uploads[#uploads + 1] = { id = id, bytes = bytes, width = width, cols = cols }
    end
    graphics.delete = function(id)
      deleted[#deleted + 1] = id
    end
    vim.api.nvim_set_hl(0, GROUP, { fg = 0x808080 })
    vim.api.nvim_set_hl(0, 'RuleSpecNoFg', { bg = 0x101010 })
  end)

  after_each(function()
    rule.stop()
    Tile.drain()
    Tile.available, graphics.upload, graphics.delete = original.available, original.upload, original.delete
  end)

  it('is nothing where there are no pixels', function()
    Tile.available = function()
      return false
    end

    eq(nil, rule.chunks(40, GROUP))
    eq(0, rule.count())
  end)

  it('is nothing when the rule is too narrow for its two faded ends', function()
    eq(nil, rule.chunks(2 * rule.FADE, GROUP))
    assert.truthy(rule.chunks(2 * rule.FADE + 1, GROUP))
  end)

  it('is nothing for a group without a foreground colour', function()
    eq(nil, rule.chunks(40, 'RuleSpecNoFg'))
  end)

  it('is as wide as asked, in display cells, for solid rules', function()
    for _, width in ipairs({ 13, 40, 44, 100 }) do
      eq(width, cells(rule.chunks(width, GROUP)))
    end
  end)

  it('is as wide as asked, in display cells, for dotted rules', function()
    for _, width in ipairs({ 13, 40, 44, 100 }) do
      eq(width, cells(rule.chunks(width, GROUP, 'dotted')))
    end
  end)

  it('reuses the same tiles for the same group and style', function()
    local first = rule.chunks(40, GROUP)
    local count = #uploads

    eq(first, rule.chunks(40, GROUP))
    eq(count, #uploads)
  end)

  it('rebuilds its tiles when the group changes colour', function()
    rule.chunks(40, GROUP)
    local count = #uploads

    vim.api.nvim_set_hl(0, GROUP, { fg = 0xffffff })
    rule.chunks(40, GROUP)

    assert.is_true(#uploads > count)
    eq(1, rule.count())
  end)

  it('caches solid and dotted rules apart', function()
    rule.chunks(40, GROUP, 'solid')
    rule.chunks(40, GROUP, 'dotted')

    eq(2, rule.count())
  end)

  it('frees every cached tile on stop', function()
    rule.chunks(40, GROUP)
    rule.chunks(40, GROUP, 'dotted')
    rule.stop()

    eq(0, rule.count())
    eq(6, #deleted)
  end)

  it('lights a solid rule at mid height and fades its left end', function()
    rule.chunks(40, GROUP, 'solid')

    local body, left = upload_of(uploads, Tile.MAX_CELLS), upload_of(uploads, rule.FADE)

    assert.is_true(alpha(body, 100, 16) > 0)
    assert.is_true(alpha(left, 1, 16) < alpha(left, 90, 16))
  end)
end)

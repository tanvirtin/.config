local hints = require('harness.ui.hints')
local Block = require('harness.transcript.Block')
local settings = require('harness.settings')

local eq = assert.are.same

describe('harness.ui.hints:', function()
  local keys = settings.keymaps:get('transcript')

  it('offers a diff its review keys', function()
    eq('gd diff · gf open · gR revert', hints.text(Block.make(Block.KIND.diff, { 'x' }), keys))
  end)

  it('offers an editing tool the git keys too', function()
    local block = Block.make(Block.KIND.tool, { 'x' }, { category = Block.CATEGORY.edit })

    eq('gd diff · gf open · gD git diff · gR revert', hints.text(block, keys))
  end)

  it('offers code only inside a fence', function()
    local block = Block.make(Block.KIND.message, { 'text', '```lua', 'x = 1', '```' }, { start = 10 })

    eq('ga apply · gi insert · gy yank', hints.text(block, keys, true))
    eq('gy yank · gF fork', hints.text(block, keys, false))
    eq(true, hints.in_code(block, 12))
    eq(false, hints.in_code(block, 10))
  end)

  it('stays quiet on blocks with nothing to do', function()
    assert.is_nil(hints.text(Block.make(Block.KIND.stop, { 'x' }), keys))
    assert.is_nil(hints.text(Block.make(Block.KIND.tool, { 'x' }, { category = Block.CATEGORY.execute }), keys))
    assert.is_nil(hints.text(nil, keys))
  end)
end)

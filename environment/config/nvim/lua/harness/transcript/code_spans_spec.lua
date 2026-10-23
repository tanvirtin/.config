local Block = require('harness.transcript.Block')
local code_spans = require('harness.transcript.code_spans')

local eq = assert.are.same

local function block(kind, lines, start)
  local made = Block.make(kind, lines)

  made.start = start

  return made
end

describe('harness.transcript.code_spans:', function()
  local blocks = {
    block(Block.KIND.prompt, { '> show me' }, 0),
    block(Block.KIND.message, { 'Here:', '```lua', 'local x = 1', '```', 'and', '```', 'plain', '```' }, 2),
    block(Block.KIND.tool, { '-> Bash ls', '```output', 'a.txt', '```' }, 11),
    block(Block.KIND.message, { '  ```py', '  print(1)', '  ```' }, 16, 1),
  }

  it('finds the code blocks of replies, in buffer rows, with their language and body', function()
    local list = code_spans.list(blocks)

    eq(3, #list)
    eq({ start = 3, finish = 5, body_start = 4, body_finish = 4, language = 'lua', lines = { 'local x = 1' } }, list[1])
    eq({ 7, 9, '' }, { list[2].start, list[2].finish, list[2].language })
    eq({ 'py', { 'print(1)' } }, { list[3].language, list[3].lines })
  end)

  it('leaves tool output and diffs out', function()
    for _, span in ipairs(code_spans.list(blocks)) do
      assert.is_true(span.start < 11 or span.start >= 16)
    end
  end)

  it('treats a fence still streaming as a block to the end of the reply', function()
    local list = code_spans.list({ block(Block.KIND.message, { 'x', '```lua', 'a', 'b' }, 0) })

    eq(
      { 1, 3, 2, 3, { 'a', 'b' } },
      { list[1].start, list[1].finish, list[1].body_start, list[1].body_finish, list[1].lines }
    )
  end)

  it('finds the block at a row, and counts blocks forward and back', function()
    local list = code_spans.list(blocks)

    eq(3, code_spans.at(list, 4).start)
    assert.is_nil(code_spans.at(list, 6))
    eq(3, code_spans.next(list, 0).start)
    eq(16, code_spans.next(list, 0, 3).start)
    eq(7, code_spans.next(list, 4).start)
    eq(7, code_spans.previous(list, 17).start)
    eq(3, code_spans.previous(list, 17, 2).start)
    assert.is_nil(code_spans.previous(list, 4))
    assert.is_nil(code_spans.next(list, 16))
  end)
end)
